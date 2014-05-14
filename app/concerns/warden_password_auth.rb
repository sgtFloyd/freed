module WardenPasswordAuth
  module WardenInstanceMethods
    def warden
      env['warden']
    end
  end

  def self.extended(base)
    base.send :include, WardenInstanceMethods

    base.use Rack::Session::Cookie, secret: 'nothingissecretontheinternet'

    base.use Warden::Manager do |config|
      config.serialize_into_session{|user| user.id}
      config.serialize_from_session{|id| User.find(id)}
      config.scope_defaults :default, strategies: [:password], action: 'auth'
      config.failure_app = base
    end

    Warden::Strategies[:password] || Warden::Strategies.add(:password) do
      def valid?
        params['user'] && params['user']['email_address'] && params['user']['password']
      end

      def authenticate!
        user = User.find_by_email_address(params['user']['email_address'])
        if user && user.authenticate(params['user']['password'])
          success!(user)
        else
          fail!
        end
      end
    end

    Warden::Manager.before_failure do |env,opts|
      env['REQUEST_METHOD'] = 'POST'
    end

  end
end
