require 'digest'
require 'haml'
require 'open-uri'
require 'redis'
require 'securerandom'
require 'sinatra'
require 'time'
require 'tlsmail'
require 'yaml'

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
  feed_page = open params['feed_url'] rescue nil
  return unless feed_page
  redis = settings.redis
  guid = SecureRandom.uuid
  redis.hmset "freed:#{guid}",
    'feed_url',       params['feed_url'],
    'notify_email',   params['notify_email'],
    'email_verified', false,
    'frequency',      params['frequency'] || 5,
    'last_checked',   Time.now.to_i,
    'last_digest',    Digest::SHA1.hexdigest(feed_page.read)
  redis.sadd "freed:feeds", guid
  send_email_verification(params['notify_email'], guid, params['feed_url'])
end

def update_feed(id)
  redis = settings.redis
  feed = redis.hgetall("freed:#{params[:id]}")
  feed_page = open feed['feed_url'] rescue nil
  return unless feed_page
  old_hash = feed['last_digest']
  new_hash = Digest::SHA1.hexdigest(feed_page.read)
  redis.hmset "freed:#{params[:id]}",
    'last_checked', Time.now.to_i,
    'last_digest',  new_hash
  old_hash != new_hash
end

def all_feeds
  redis = settings.redis
  Hash[redis.smembers("freed:feeds").inject({}) do |feeds, feed_id|
    feeds[feed_id] = redis.hgetall("freed:#{feed_id}"); feeds
  end.sort_by{|id, feed| -feed['last_checked'].to_i}]
end

# ============================== EMAILS ============================== #

def send_email_verification(recipient, feed_id, feed_url)
  send_email( recipient, 'verify_email',
    {feed_id: feed_id, feed_url: feed_url})
end

def send_update_email(feed_id)
  feed = settings.redis.hgetall("freed:#{feed_id}")
  send_email( feed['notify_email'], 'feed_updated',
    {feed_url: feed['feed_url']})
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
end

# ============================== SINATRA ============================== #

configure do
  load_config 'config/freed.yml' do |conf|
    redistogo = URI.parse conf[:redis]
    set :redis => Redis.new(:host => redistogo.host,
                            :port => redistogo.port,
                            :password => redistogo.password)
    set :gmail_user => conf[:gmail_user],
        :gmail_pass => conf[:gmail_pass]
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
  changed = update_feed(params)
  send_update_email(params[:id]) if changed
end

# DELETE
delete '/feed/:id' do
  redis = settings.redis
  if redis.sismember('freed:feeds', params[:id])
    redis.srem("freed:feeds", params[:id])
    redis.del("freed:#{params[:id]}")
  end
end

get '/feed/verify/:id' do
  redis = settings.redis
  if redis.sismember('freed:feeds', params[:id])
    redis.hset("freed:#{params[:id]}", 'email_verified', true)
  end
  redirect '/'
end
