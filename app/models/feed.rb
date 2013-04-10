require 'securerandom'

class Feed
  attr_accessor :id,
                :feed_url,        # URL of the page to check
                :notify_email,    # Email address to notify when this feed updates
                :email_verified,  # Whether notify_email has been verified
                :frequency,       # How often feed is checked (in minutes)
                :last_checked,    # Unix timestamp of the last check
                :last_digest      # Digest of the page content from the check

  def initialize(params={})
    params = {frequency: 5}.merge(params) # default values
    params.each do |param, value|
      self.send("#{param}=", value)
    end
  end

  def self.create(params={})
    feed = self.new(params)
    feed.id = SecureRandom.uuid[0...8]
    feed.email_verified = false
    feed
  end

  def save
    # before save verifications
    save_to_redis
    # after save confirmation email
  end

private

  def save_to_redis
    settings.redis.hmset "freed:#{self.id}",
      'feed_url',       self.feed_url,
      'notify_email',   self.notify_email,
      'email_verified', self.email_verified,
      'frequency',      self.frequency,
      'last_checked',   self.last_checked,
      'last_content',   feed_page,
      'last_digest',    Digest::SHA1.hexdigest(feed_page)

    settings.redis.sadd "freed:feeds", self.id
  end

end
