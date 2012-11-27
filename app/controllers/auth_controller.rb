require 'google/api_client'

class AuthController < ApplicationController
  before_filter :authenticate

  def self.google_authorization
    if @client.blank?
      @client = Google::APIClient.new
      @client.authorization.client_id = Settings.google_proxy.client_id
      @client.authorization.client_secret = Settings.google_proxy.client_secret
      @client.authorization.redirect_uri = Settings.google_proxy.client_redirect_uri
      @client.authorization.scope = ['https://www.googleapis.com/auth/userinfo.profile',
        'https://www.googleapis.com/auth/userinfo.email',
        'https://www.googleapis.com/auth/calendar',
        'https://www.googleapis.com/auth/tasks']
    end
    @client.authorization
  end

  def google_request_access
    new_auth = self.class.google_authorization.dup
    new_auth.state = params[:final_redirect]
    new_auth.state ||= "/dashboard"
    new_auth.state = Base64.encode64 new_auth.state
    redirect_to new_auth.authorization_uri.to_s
  end

  def google_auth_callback
    new_auth = self.class.google_authorization.dup

    final_redirect = params[:state]
    final_redirect ||= "/dashboard"
    final_redirect = Base64.decode64 final_redirect

    if !params[:error].blank?
      # remove token if access_denied
      Oauth2Data.delete_all(:uid => session[:user_id], :app_id => "google") if params[:error] == "access_denied"
    elsif !params[:code].blank?
      new_auth.code = params[:code]
      new_auth.fetch_access_token!
      Oauth2Data.new_or_update(
        session[:user_id],
        "google",
        new_auth.access_token.to_s,
        new_auth.refresh_token,
        new_auth.issued_at.to_i + new_auth.expires_in
      )
    end

    redirect_to final_redirect
  end

end