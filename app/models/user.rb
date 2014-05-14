class User < ActiveRecord::Base
  validates_presence_of :email_address, :password
  validates_uniqueness_of :email_address

  def authenticate(attempted_password)
    attempted_password == self.password
  end
end
