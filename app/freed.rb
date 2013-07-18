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

load 'app/models/feed.rb'

def load_config(config, &block)
  yield YAML.load_file(config)
end

def delete_feed(id, sig)
  if feed = Feed.find(id, sig)
    feed.destroy
  else
    send_delete_verification_email(id)
  end
end

def verify_feed(id, sig)
  return unless feed = Feed.find(id, sig)
  feed.email_verified = true
  feed.save
end

def feed_signature(id)
  Digest::SHA1.hexdigest(id + settings.secret_hash_key)[0...8]
end

# ============================== EMAILS ============================== #

def send_delete_verification_email(feed_id)
  feed = settings.redis.hgetall("freed:#{feed_id}")
  feed_sig = feed_signature(feed_id)
  send_email(feed['notify_email'], 'verify_delete',
    {feed_id: feed_id, feed_url: feed['feed_url'], feed_sig: feed_sig} )
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
    FREED_URL = conf[:freed_url]
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
  haml :index, :locals => { :feeds => Feed.all }
end

# CREATE
post '/feed' do
  Feed.create(params)
  redirect '/'
end

# UPDATE
put '/feed/:id' do
  Feed.find(params[:id], params[:sig]).try(&:update)
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
