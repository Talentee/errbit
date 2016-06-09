require 'recurse'

class Notice < ActiveRecord::Base
  include Authority::Abilities
  include NoticeRepository

  serialize :server_environment, Hash
  serialize :request, Hash
  serialize :notifier, Hash
  serialize :user_attributes, Hash
  serialize :current_user, Hash

  delegate :lines, :to => :backtrace, :prefix => true
  delegate :app, :to => :problem

  belongs_to :problem
  belongs_to :backtrace

  counter_culture :problem

  after_commit :unresolve_problem, on: :create
  after_commit :cache_attributes_on_problem, on: :create
  after_commit :increase_in_distributions, on: :create
  after_commit :decrease_in_distributions, on: :destroy

  before_save :sanitize
  after_initialize :default_values

  validates_presence_of :backtrace, :server_environment, :notifier

  def default_values
    if self.new_record?
      self.server_environment ||= Hash.new
      self.request ||= Hash.new
      self.notifier ||= Hash.new
      self.user_attributes ||= Hash.new
      self.current_user ||= Hash.new
    end
  end

  def message_signature
    m = message.clone
    m.gsub!(/".+?"/, '"%STR%"')
    m.gsub!(/'.+?'/, '\'%STR%\'')
    m.gsub!(/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/, '%UUID%')
    m.gsub!(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/, '%IP%')
    m.gsub!(/0x\h+/, '%HEX%')
    m.gsub!(/\h{7,}/, '%HEXSTR%')
    m.gsub!(/\d+/, '%NUM%')
    m.truncate(150)
  end

  def user_agent
    agent_string = env_vars['HTTP_USER_AGENT']
    agent_string.blank? ? nil : UserAgent.parse(agent_string)
  end

  def user_agent_string
    if user_agent.nil? || user_agent.none?
      "N/A"
    else
      "#{user_agent.browser} #{user_agent.version} (#{user_agent.os})"
    end
  end

  def environment_name
    server_environment['server-environment'] || server_environment['environment-name']
  end

  def component
    request['component']
  end

  def action
    request['action']
  end

  def where
    where = component.to_s.dup
    where << "##{action}" if action.present?
    where
  end

  def request
    super || {}
  rescue Psych::SyntaxError
    # some notices may have incorrect yaml inside request field
    {}
  end

  def url
    request['url']
  end

  def host
    uri = url && URI.parse(url)
    uri.blank? ? "N/A" : uri.host
  rescue URI::InvalidURIError
    "N/A"
  end

  def env_vars
    request['cgi-data'] || {}
  end

  def params
    request['params'] || {}
  end

  def session
    request['session'] || {}
  end

  def in_app_backtrace_lines
    backtrace_lines.in_app
  end

  def similar_count
    problem.notices_count
  end

  def emailable?
    app.email_at_notices.include?(problem.notices_count_since_unresolve)
  end

  def should_email?
    app.emailable? && emailable?
  end

  def should_notify?
    app.notification_service_configured? &&
    (app.notification_service.notify_at_notices.include?(0) || app.notification_service.notify_at_notices.include?(problem.notices_count_since_unresolve))
  end

  ##
  # TODO: Move on decorator maybe
  #
  def project_root
    if server_environment
      server_environment['project-root'] || ''
    end
  end

  def app_version
    if server_environment
      server_environment['app-version'] || ''
    end
  end

  protected
  def increase_in_distributions
    problem.increase_in_message_distribution message_signature
    problem.increase_in_host_distribution host
    problem.increase_in_user_agent_distribution user_agent_string
  end

  def decrease_in_distributions
    problem.decrease_in_message_distribution message_signature
    problem.decrease_in_host_distribution host
    problem.decrease_in_user_agent_distribution user_agent_string
  end

  def unresolve_problem
    return if problem.unresolved?
    problem.unresolve!
  end

  def cache_attributes_on_problem
    ProblemUpdaterCache.new(problem, self).update
  end

  def sanitize
    [:server_environment, :request, :notifier].each do |h|
      send("#{h}=",sanitize_hash(send(h)))
    end
  end

  def sanitize_hash(h)
    h.recurse do
      |h| h.inject({}) do |h,(k,v)|
        if k.is_a?(String)
          h[k.gsub(/\./,'&#46;').gsub(/^\$/,'&#36;')] = v
        else
          h[k] = v
        end
        h
      end
    end
  end
end

