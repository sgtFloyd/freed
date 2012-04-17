require 'haml'
require 'sinatra'

get '/' do
  haml :index
end

post '/feed' do
  # params: feed_url, notify_email, frequency
end
