class ApplicationController < ActionController::Base
  include Pundit
  protect_from_forgery
  before_filter :get_settings, :initialize_calcentral_config
  before_filter :check_reauthentication
  after_filter :access_log
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Disable most of the default headers provided by secure_headers gem, leaving just x-frame for now
  # http://rubydoc.info/gems/secure_headers/0.5.0/frames
  # Rails 4 will DENY X-Frame by default
  ensure_security_headers
  skip_before_filter :set_csp_header, :set_hsts_header, :set_x_content_type_options_header, :set_x_xss_protection_header

  def authenticate
    redirect_to url_for_path('/auth/cas') unless session[:user_id]
  end

  # TODO see if we can standardize empty responses. We have 2 forms: This one, which returns empty JSON and
  # an HTTP 200 status, and another form that returns empty body with 401 status.
  def api_authenticate
    if session[:user_id].blank?
      Rails.logger.warn "Authenticated user absent in request to #{controller_name}\##{action_name}"
      render :json => {}.to_json
    end
  end

  def api_authenticate_401
    if session[:user_id].blank?
      Rails.logger.warn "Authenticated user absent in request to #{controller_name}\##{action_name}"
      render :nothing => true, :status => 401
    end
  end

  def is_admin?
    (real_user && real_user.is_superuser==true)
  end

  def reauthenticate
    delete_reauth_cookie
    redirect_to url_for_path("/auth/cas?renew=true")
  end

  def check_reauthentication
    unless !!session[:user_id]
      delete_reauth_cookie
      return
    end
    return unless Settings.features.reauthentication
    return unless is_admin?
    reauthenticate if acting_as? && !cookies[:reauthenticated]
  end

  def delete_reauth_cookie
    cookies.delete :reauthenticated
  end

  def current_user
    @current_user ||= User::Auth.get(session[:user_id])
  end

  def acting_as?
    !!((session[:original_user_id] && session[:user_id]) && (session[:original_user_id] != session[:user_id]))
  end

  def real_uid
    (acting_as?) ? session[:original_user_id] : session[:user_id]
  end

  def real_user
    return false unless real_uid
    @real_user ||= User::Auth.get(real_uid)
  end

  def act_as_uid
    return (acting_as?) ? session[:user_id] : nil
  end

  # override of Rails default behavior:
  # reset session AND return 401 when CSRF token validation fails
  def handle_unverified_request
    reset_session
    render :nothing => true, :status => 401
  end

  # Rails url_for defaults the protocol to "request.protocol". But if SSL is being
  # provided by Apache or Nginx, the reported protocol will be "http://". To fix
  # callback URLs, we need to override.
  def default_url_options
    if defined?(Settings.application.protocol) && !Settings.application.protocol.blank?
      Rails.logger.debug("Setting default URL protocol to #{Settings.application.protocol}")
      {protocol: Settings.application.protocol}
    else
      {}
    end
  end

  def clear_cache
    authorize(current_user, :can_clear_cache?)
    Rails.logger.info "Clearing all cache entries"
    Rails.cache.clear
    render :nothing => true, :status => 204
  end

  def ping
    # IST's nagios and our check-alive.sh script use this endpoint to tell whether the server's up.
    # Don't modify its content unless you have general agreement that it's necessary to do so.
    ping_state = do_ping
    if ping_state
      render :json => {
        :server_alive => true
      }.to_json
    else
      render :nothing => true, :status => 503
    end
  end

  def user_not_authorized(error)
    Rails.logger.warn "Unauthorized request made by UID: #{session[:user_id]} to #{controller_name}\##{action_name}: #{error.message}"
    render :nothing => true, :status => 403
  end

  def handle_api_exception(error)
    Rails.logger.error "#{error.class} raised with UID: #{session[:user_id]} in #{controller_name}\##{action_name}: #{error.message}"
    render json: { :error => error.message }.to_json, status: 500
  end

  def handle_client_error(error)
    case error.class.to_s
      when 'Errors::BadRequestError'
        Rails.logger.debug "Bad request made to #{controller_name}\##{action_name}: #{error.message}"
        render text: error.message, status: 400 and return
      else
        Rails.logger.error "Unknown Error::ClientError handled in #{controller_name}\##{action_name}: #{error.class} - #{error.message}"
        render json: {:error => error.message}.to_json, status: 500 and return
    end
  end

  private

  def do_ping
    # rate limit so we don't check server status excessively often
    Rails.cache.fetch(
      "server_ping_#{ServerRuntime.get_settings["hostname"]}",
      :expires_in => 30.seconds) {
      if !User::Data.database_alive?
        raise "CalCentral database is currently unavailable"
      end
      if !CampusOracle::Queries.database_alive?
        raise "Campus database is currently unavailable"
      end
      true
    }
  end

  def get_settings
    @server_settings = ServerRuntime.get_settings
  end

  def initialize_calcentral_config
    @calcentral_config = {
      "applicationVersion" => ServerRuntime.get_settings["versions"]["application"],
      "clientHostname" => ServerRuntime.get_settings["hostname"],
      "googleAnalyticsId" => Settings.google_analytics_id,
      "sentryUrl" => Settings.sentry_url
    }.to_json.html_safe
  end

  def access_log
    # HTTP_X_FORWARDED_FOR is the client's IP when we're behind Apache; REMOTE_ADDR otherwise
    remote = request.env["HTTP_X_FORWARDED_FOR"] || request.env["REMOTE_ADDR"]
    line = "ACCESS_LOG #{remote} #{request.request_method} #{request.filtered_path} #{status}"
    if session[:original_user_id]
      line += " uid=#{session[:original_user_id]}_acting_as_uid=#{session[:user_id]}"
    else
      line += " uid=#{session[:user_id]}"
    end
    line += " class=#{self.class.name} action=#{params["action"]} view=#{view_runtime}ms db=#{db_runtime}ms"
    logger.warn line
  end

  # When given a relative path string as its first argument, Rails's redirect_to method ignores
  # the protocol setting in default_url_options, and instead fills in the URL protocol from the
  # request referer. Behind nginx or Apache, this causes a double redirect in the browser,
  # first to "http:" and then to "https:". This method makes relative paths safer to use.
  def url_for_path(path)
    if (protocol = default_url_options[:protocol])
      protocol + request.host_with_port + path
    else
      path
    end
  end

  def disable_xframe_options
    response.headers.except! 'X-Frame-Options'
  end

end
