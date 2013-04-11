class Feed
  attr_accessor :id,
                :feed_url,        # URL of the page to check
                :notify_email,    # Email address to notify when this feed's page changes
                :email_verified,  # Whether notify_email has been verified
                :frequency,       # How often feed's page is checked (in minutes)
                :last_checked,    # Unix timestamp of the last check
                :last_content,    # Page content from the last check
                :last_digest      # Digest of the page content from the last check

  private_class_method :new

  VALID_EMAIL = /\A[\w+]+@\w+\.\w+\Z/

  def initialize(params={})
    params = {frequency: 5}.merge(params) # default values
    params.each do |param, value|
      send("#{param}=", value)
    end
  end

  def self.create(params={})
    params[:id] = SecureRandom.uuid[0...8]
    params[:email_verified] = false
    params[:last_checked] = Time.now.to_i
    new(params)
  end

  def page_content
    @_page_content ||= open(self.feed_url).read rescue nil
  end

  def page_digest
    @_page_digest ||= Digest::SHA1.hexdigest(self.page_content) rescue nil
  end

  def persisted?
    settings.redis.sismember('freed:feeds', self.id)
  end

  def new_record?
    !persisted?
  end

  def save
    return unless valid?
    new_feed = self.new_record?
    save_to_redis
    # send_verification_email if new_feed
  end

  def valid?
    return false unless self.notify_email =~ VALID_EMAIL
    return false unless self.page_content
    true
  end

private

  def save_to_redis
    settings.redis.hmset "freed:#{self.id}",
      'feed_url',       self.feed_url,
      'notify_email',   self.notify_email,
      'email_verified', self.email_verified,
      'frequency',      self.frequency,
      'last_checked',   self.last_checked,
      'last_content',   self.page_content,
      'last_digest',    self.page_digest
    settings.redis.sadd "freed:feeds", self.id
  end

end
