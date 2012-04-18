require 'digest'
require 'haml'
require 'open-uri'
require 'redis'
require 'securerandom'
require 'sinatra'
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
  # TODO: send verification email
end

def all_feeds
  redis = settings.redis
  Hash[redis.smembers("freed:feeds").inject({}) do |feeds, feed_id|
    feeds[feed_id] = redis.hgetall("freed:#{feed_id}"); feeds
  end.sort_by{|id, feed| -feed['last_checked'].to_i}]
end

# ============================== SINATRA ============================== #

configure do
  load_config 'config/freed.yml' do |conf|
    redistogo = URI.parse conf[:redis]
    set :redis => Redis.new(:host => redistogo.host,
                            :port => redistogo.port,
                            :password => redistogo.password)
  end
end

get '/' do
  haml :index, :locals => { :feeds => all_feeds }
end

post '/feed' do
  save_feed params
  redirect '/'
end

delete '/feed/:id' do
  redis = settings.redis
  redis.srem("freed:feeds", params[:id])
  redis.del("freed:#{params[:id]}")
end
