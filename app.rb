require 'sha1'
require 'rubygems'
require 'haml'
require 'sinatra'
require 'xml-object'
require 'lib/bumble'
require 'java'
import com.google.appengine.api.users.UserServiceFactory;

# TODO: fork Bumble from github.com/olabini/bumble and make this change in the lib instead
module Bumble
  module ClassMethods
    alias_method :find_without_id, :find
    def find(conditions={})
      if conditions.is_a?(String) or conditions.is_a?(Integer)
        get(conditions) rescue nil
      else
        find_without_id(conditions)
      end
    end
  end
end

# models
# ------

class Account
  include Bumble
  ds :email, :apikey
  has_many :applications, :Application, :account_id, :iorder => :name
  def self.generate_apikey() SHA1.hexdigest((0..50).inject('') { |s, i| s << rand(93) + 33; s }) end
end

class Application
  include Bumble
  ds :account_id, :name, :github_url
  belongs_to :account, Account
  has_many :errors, :Error, :application_id, :iorder => :created_at
end

class Error
  include Bumble
  ds :application_id, :active, :created_at, :message, :backtrace, :rails_root, :url, :host, :ip, :parameters, :process
  belongs_to :application, :Application
  alias_method :created_at_without_typecasting, :created_at
  def created_at
    val = created_at_without_typecasting
    Time.parse(val.to_string)
  end
end

# actions
# -------

UserService = UserServiceFactory.user_service

get '/' do  
  if current_user
    @account = get_account
    @apps = @account.applications
    haml :dashboard
  else
    haml :welcome
  end
end

get '/apps/:id' do
  ensure_logged_in
  if @app = Application.find(params[:id]) and (@app.account_id == get_account.key or admin?)
    @errors = Error.all({:application_id => @app.key, :active => params[:active] != 'no'}, :iorder => 'created_at')
    haml :app
  else
    status 404; "Not found."
  end
end

get '/apps/:id/setup' do
  ensure_logged_in
  if @app = Application.find(params[:id]) and (@app.account_id == get_account.key or admin?)
    haml :setup
  else
    status 404; "Not found."
  end
end

post '/apps' do
  ensure_logged_in
  if params[:name] =~ /^[a-z0-9_]+$/i
    app = Application.create(
      :account_id => get_account.key,
      :name       => params[:name]
    )
    redirect "/apps/#{app.key}"
  else
    "App name can only contain characters a-z, 0-9, and underscore."
  end
end

put '/apps/:id' do
  ensure_logged_in
  if @app = Application.find(params[:id]) and @app.account_id == get_account.key
    @app.github_url = params[:github_url]
    @app.save!
    redirect "/apps/#{@app.key}"
  else
    status 404; "Not found."
  end
end

delete '/apps/:id' do
  ensure_logged_in
  if @app = Application.find(params[:id]) and @app.account_id == get_account.key
    if params[:sure] == 'yes'
      @app.delete!
      redirect '/'
    else
      "You must check the box."
    end
  else
    status 404; "Not found."
  end
end

get '/login' do
  redirect UserService.create_login_url(params[:from] || '/')
end

get '/logout' do
  redirect UserService.create_logout_url('/')
end

post '/errors' do
  data = XMLObject.new(request.body)
  if data.apikey and account = Account.find(:apikey => data.apikey) and
  data.appid and application = Application.find(data.appid) and
  application.account_id == account.key
    begin
      Error.create(
        :application_id => application.key,
        :created_at     => Time.now,
        :message        => unescape_html(data.message),
        :backtrace      => unescape_html(data.backtrace),
        :rails_root     => unescape_html(data.rails_root),
        :url            => unescape_html(data.url),
        :host           => unescape_html(data.host),
        :ip             => unescape_html(data.ip),
        :parameters     => unescape_html(data.parameters),
        :process        => unescape_html(data.process),
        :active         => true
      )
    rescue => e
      "<status response=\"error\"><message>#{h e.message}<message></status>"
    else
      '<status response="saved"/>'
    end
  else
    status 500
    '<status response="error"><message>Invalid apikey or appid or unauthorized.</message></status>'
  end
end

get '/errors' do
  ensure_logged_in
  if admin?
    @errors = Error.all({:active => true}, :iorder => 'created_at')
    haml :errors
  else
    status 401; "Unauthorized."
  end
end

get '/errors/:id' do
  ensure_logged_in
  if @error = Error.find(params[:id]) and (@error.application.account_id == get_account.key or admin?)
    haml :error
  else
    status 404; "Not found."
  end
end

put '/errors/:id' do
  ensure_logged_in
  if @error = Error.find(params[:id]) and (@error.application.account_id == get_account.key or admin?)
    if params[:active]
      @error.active = params[:active] =~ /inactive/i ? false : true
    end
    @error.save!
    redirect "/errors/#{@error.key}"
  else
    status 404; "Not found."
  end
end

def ensure_logged_in
  unless current_user
    redirect "/login?from=#{request.path}"
    halt
  end
end

helpers do
  def current_user() UserService.user_logged_in? && UserService.current_user end
  def admin?() UserService.user_logged_in? && UserService.user_admin? end
  def get_account
    Account.find(:email => current_user.email) ||
      Account.create(:email => current_user.email, :apikey => Account.generate_apikey)
  end
  include Rack::Utils
  alias_method :h, :escape_html
  def unescape_html(html)
    html.gsub(/&(quot|lt|gt);/) do |match|
      {'quot' => '"', 'lt' => '<', 'gt' => '>'}[$1]
    end
  end
  def linkify_backtrace(backtrace, github_url)
    if github_url.to_s.any? and github_url =~ /^http:\/\/github.com/
      github_url.sub!(/\/$/, '')
      github_url.sub!(/\/tree\/master$/, '')
      backtrace.gsub(/(app\/[^:]+):(\d+)/) do |match|
        "<a href=\"#{github_url}/blob/master/#{$1}#L#{$2}\">#{match}</a>"
      end
    else
      backtrace
    end
  end
end
