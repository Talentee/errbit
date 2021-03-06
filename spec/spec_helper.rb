# This file is copied to ~/spec when you run 'ruby script/generate rspec'
# from the project root directory.
ENV["RAILS_ENV"] ||= 'test'

if ENV['COVERAGE']
  require 'coveralls'
  require 'simplecov'
  Coveralls.wear!('rails') do
    add_filter 'bundle'
  end
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ]
  SimpleCov.start('rails') do
    add_filter 'bundle'
  end
end

require File.expand_path("../../config/environment", __FILE__)
require 'rspec/rails'
require 'database_cleaner'
require 'webmock/rspec'
require 'xmpp4r'
require 'xmpp4r/muc'
require 'sidekiq/testing'


# Requires supporting files with custom matchers and macros, etc,
# in ./support/ and its subdirectories.
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each {|f| require f}

Fabrication.configure do |config|
  fabricator_dir = "spec/fabricators"
end

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!
  config.mock_with :rspec do |mocks|
    mocks.yield_receiver_to_any_instance_implementation_blocks = false
  end

  config.include Devise::TestHelpers, :type => :controller
  config.use_transactional_fixtures = false

  config.include WebMock::API
  Sidekiq::Testing.inline!

  config.include Haml, :type => :helper
  config.include Haml::Helpers, :type => :helper
  config.before(:each, :type => :helper) do |config|
    init_haml_helpers
  end

  config.after(:all) do
    WebMock.disable_net_connect! :allow => /coveralls\.io/
  end

  config.before(:suite) do
    DatabaseCleaner.strategy = :deletion
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end

OmniAuth.config.test_mode = true

ServiceLocator.differ = FakeDiffer
