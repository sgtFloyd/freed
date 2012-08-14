require 'differ'
require 'digest'
require 'haml'
require 'open-uri'
require 'redis'
require 'securerandom'
require 'sinatra'
require 'time'
require 'tlsmail'
require 'yaml'

VALID_EMAIL = /\w+@\w+\.\w+/

def load_config(config, &block)
  yield YAML.load_file(config)
end

# feeds stored in redis hash:
#   feed_id => {
#     feed_url:       string
#     notify_email:   string
#     email_verified: 0/1
#     frequency:      int (in minutes)
#     last_checked:   int (in seconds since epoch)
#     last_hash:      hex digest of last page load
#   }

def save_feed(params)
  feed_page = open(params['feed_url']).read rescue nil
  return unless feed_page && params['notify_email'] =~ VALID_EMAIL
  guid = SecureRandom.uuid[0...8]
  settings.redis.hmset "freed:#{guid}",
    'feed_url',       params['feed_url'],
    'notify_email',   params['notify_email'],
    'email_verified', false,
    'frequency',      params['frequency'] || 5,
    'last_checked',   Time.now.to_i,
    'last_content',   feed_page,
    'last_digest',    Digest::SHA1.hexdigest(feed_page)
  settings.redis.sadd "freed:feeds", guid
  send_email_verification(params['notify_email'], guid, params['feed_url'])
end

def update_feed(id, sig)
  return unless sig == feed_signature(id)
  feed = settings.redis.hgetall("freed:#{id}")
  feed_page = open(feed['feed_url']).read rescue nil
  return unless feed_page
  old_cont, old_hash = feed['last_content'], feed['last_digest']
  new_cont, new_hash = feed_page, Digest::SHA1.hexdigest(feed_page)

  settings.redis.hmset "freed:#{id}",
    'last_checked', Time.now.to_i,
    'last_content', new_cont,
    'last_digest',  new_hash
  if old_hash != new_hash
    diff = Differ.diff_by_line(new_cont, old_cont)
    changes = diff.instance_variable_get(:@raw).select{|r| Differ::Change === r}
    send_update_email(id, changes)
  end
end

def delete_feed(id, sig)
  if sig == feed_signature(id)
    redis = settings.redis
    if redis.sismember('freed:feeds', id)
      redis.srem("freed:feeds", id)
      redis.del("freed:#{id}")
    end
  else
    send_delete_verification_email(id)
  end
end

def verify_feed(id, sig)
  return unless sig == feed_signature(id)
  redis = settings.redis
  if redis.sismember('freed:feeds', id)
    redis.hset("freed:#{id}", 'email_verified', true)
  end
end

def all_feeds
  redis = settings.redis
  Hash[redis.smembers("freed:feeds").inject({}) do |feeds, feed_id|
    feeds[feed_id] = redis.hgetall("freed:#{feed_id}"); feeds
  end.sort_by{|id, feed| -feed['last_checked'].to_i}]
end

def feed_signature(id)
  Digest::SHA1.hexdigest(id + settings.secret_hash_key)[0...8]
end

# ============================== EMAILS ============================== #

def send_email_verification(recipient, feed_id, feed_url)
  feed_sig = feed_signature(feed_id)
  send_email( recipient, 'verify_email',
    {feed_id: feed_id, feed_url: feed_url, feed_sig: feed_sig} )
end

def send_delete_verification_email(feed_id)
  feed = settings.redis.hgetall("freed:#{feed_id}")
  feed_sig = feed_signature(feed_id)
  send_email(feed['notify_email'], 'verify_delete',
    {feed_id: feed_id, feed_url: feed['feed_url'], feed_sig: feed_sig} )
end

def send_update_email(feed_id, changes)
  feed = settings.redis.hgetall("freed:#{feed_id}")
  send_email( feed['notify_email'], 'feed_updated',
    {feed_url: feed['feed_url'], changes: changes})
end

def send_email(recipient, template, locals)
  from = settings.gmail_user + '@gmail.com'
  content = Haml::Engine.new( File.open("app/views/email/#{template}.haml").read )
            .render( Object.new, locals.merge(:to => recipient, :from => from) )
  Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
  Net::SMTP.start('smtp.gmail.com', 587, 'gmail.com', from, settings.gmail_pass, :login) do |smtp|
    smtp.send_message(content, from, recipient)
  end
rescue => e
  puts "Caught: #{e}"
end

# ============================== SINATRA ============================== #

configure do
  load_config 'config/freed.yml' do |conf|
    redistogo = URI.parse conf[:redis]
    set :redis => Redis.new(:host => redistogo.host,
                            :port => redistogo.port,
                            :password => redistogo.password)
    set :gmail_user => conf[:gmail_user],
        :gmail_pass => conf[:gmail_pass],
        :secret_hash_key => conf[:secret_hash_key]
  end
end

get '/' do
  haml :index, :locals => { :feeds => all_feeds }
end

# CREATE
post '/feed' do
  save_feed params
  redirect '/'
end

# UPDATE
put '/feed/:id' do
  update_feed params[:id], params[:sig]
end

# DELETE
delete '/feed/:id' do
  delete_feed params[:id], params[:sig]
end

# Verify feed via email link
get '/feed/:id/verify' do
  verify_feed params[:id], params[:sig]
  redirect '/'
end

# Delete feed vie email link
get '/feed/:id/delete' do
  delete_feed params[:id], params[:sig]
  redirect '/'
end
