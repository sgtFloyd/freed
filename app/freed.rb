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

configure do
  conf = YAML.load_file('config/freed.yml')
  FREED_URL = conf[:freed_url]
  redistogo = URI.parse conf[:redis]
  set :redis => Redis.new(:host => redistogo.host,
                          :port => redistogo.port,
                          :password => redistogo.password)
  set :gmail_user => conf[:gmail_user],
      :gmail_pass => conf[:gmail_pass],
      :secret_hash_key => conf[:secret_hash_key]
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
  id, sig = params[:id], params[:sig]
  Feed.find(id, sig).try(:update)
end

# DELETE
delete '/feed/:id' do
  Feed.destroy params[:id], params[:sig]
end

# Verify feed via email link
get '/feed/:id/verify' do
  id, sig = params[:id], params[:sig]
  Feed.find(id, sig).try(:verify)
  redirect '/'
end

# Delete feed via email link
get '/feed/:id/delete' do
  Feed.destroy params[:id], params[:sig]
  redirect '/'
end

class Email
  def self.send(recipient, template, locals)
    from = settings.gmail_user + '@gmail.com'
    content = Haml::Engine.new( File.open("app/views/email/#{template}.haml").read )
              .render( Object.new, locals.merge(:to => recipient, :from => from) )
    Net::SMTP.enable_tls(OpenSSL::SSL::VERIFY_NONE)
    Net::SMTP.start('smtp.gmail.com', 587, 'gmail.com', from, settings.gmail_pass, :login) do |smtp|
      smtp.send_message(content, from, recipient)
    end
  rescue => e
    puts "Failure sending email: #{e}"
  end
end
