# frozen_string_literal: true

require "securerandom"
require "simplecov"

SimpleCov.start do
  add_filter "/test/"
end

ENV["SECRET_KEY_BASE"] ||= SecureRandom.hex(64)
ENV["RAILS_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["DB_USER"] ||= "postgres"
ENV["DB_PASSWORD"] ||= "postgres"
ENV["DB_HOST"] ||= "localhost"
ENV["DB_PORT"] ||= "5432"
ENV["DB_NAME_TEST"] ||= ENV.fetch("DB_NAME", "gem_template_test")
db_user = ENV.fetch("DB_USER", nil)
db_password = ENV.fetch("DB_PASSWORD", nil)
db_host = ENV.fetch("DB_HOST", nil)
db_port = ENV.fetch("DB_PORT", nil)
db_name_test = ENV.fetch("DB_NAME_TEST", nil)

ENV["PGUSER"] ||= db_user
ENV["PGPASSWORD"] ||= db_password
ENV["DATABASE_URL"] ||= "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name_test}"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)

require "minitest/autorun"
require "rails"

module RecordingStudioTestDataHelpers
  def reset_recording_studio_tables!(*recordable_classes)
    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.unscoped.update_all(parent_recording_id: nil, root_recording_id: nil)
    RecordingStudio::Recording.unscoped.delete_all

    recordable_classes.compact.uniq.each(&:delete_all)
    Workspace.delete_all if defined?(Workspace)
    User.delete_all if defined?(User)
  end
end

require File.expand_path("dummy/config/environment", __dir__)
require "rails/test_help"
require "recording_studio"
require "devise/test/integration_helpers"

ActiveSupport::TestCase.class_eval do
  include RecordingStudioTestDataHelpers

  def assert_not(value, message = nil)
    assert_equal false, !!value, message
  end

  def assert_not_nil(value, message = nil)
    assert_equal false, value.nil?, message
  end
end

Minitest::Test.class_eval do
  def assert_not(value, message = nil)
    assert_equal false, !!value, message
  end

  def assert_not_nil(value, message = nil)
    assert_equal false, value.nil?, message
  end
end

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers

    MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    def create_user(
      name: "Test User",
      email: "user-#{SecureRandom.hex(4)}@example.com",
      admin: false
    )
      User.create!(
        name: name,
        email: email,
        password: "password123",
        password_confirmation: "password123",
        admin: admin
      )
    end

    def sign_in_as(user)
      sign_in user, scope: :user
    end

    def modern_headers(extra_headers = {})
      { "HTTP_USER_AGENT" => MODERN_USER_AGENT }.merge(extra_headers)
    end
  end
end
