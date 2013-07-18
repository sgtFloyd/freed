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

  FEED_INDEX = "freed:feeds"
  VALID_EMAIL = /\A[\w+]+@\w+\.\w+\Z/

  def initialize(params={})
    params = {frequency: 5}.merge(params) # default values
    params.each do |param, value|
      send("#{param}=", value)
    end
  end

  def self.all
    feed_ids = settings.redis.smembers(FEED_INDEX)
    feeds = feed_ids.map(&method(:load_from_redis))
    feeds.sort_by{|feed| -feed.last_checked.to_i}
  end

  def self.create(params={})
    params[:id] = SecureRandom.uuid[0...8]
    params[:email_verified] = false
    params[:last_checked] = Time.now.to_i
    new(params)
  end

  def self.find(id, sig)
    return unless sign(id) == sig
    load_from_redis(id)
  end

  def destroy
    remove_from_redis
  end

  def page_content
    @_page_content ||= open(self.feed_url).read rescue nil
  end

  def page_digest
    @_page_digest ||= Digest::SHA1.hexdigest(self.page_content) rescue nil
  end

  def persisted?
    settings.redis.sismember(FEED_INDEX, self.id)
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

  def signature
    sign(self.id)
  end

  def valid?
    return false unless self.notify_email =~ VALID_EMAIL
    return false unless self.page_content
    true
  end

private

  def self.load_from_redis(id)
    return unless settings.redis.sismember(FEED_INDEX, id)
    new settings.redis.hgetall("freed:#{id}").merge(id: id)
  end

  def self.sign(id, length=8)
    Digest::SHA1.hexdigest([id, settings.secret_hash_key].join)[0, length]
  end

  def remove_from_redis
    settings.redis.srem FEED_INDEX, self.id
    settings.redis.del "freed:#{self.id}"
  end

  def save_to_redis
    settings.redis.hmset "freed:#{self.id}",
      'feed_url',       self.feed_url,
      'notify_email',   self.notify_email,
      'email_verified', self.email_verified,
      'frequency',      self.frequency,
      'last_checked',   self.last_checked,
      'last_content',   self.page_content,
      'last_digest',    self.page_digest
    settings.redis.sadd FEED_INDEX, self.id
  end

end
