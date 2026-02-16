# frozen_string_literal: true

require "simplecov"
require "rails"

SimpleCov.start

ENV["RAILS_ENV"] ||= "test"
ENV["RACK_ENV"] ||= "test"

module FlatPack
  class Engine < ::Rails::Engine; end
end

require_relative "../config/environment"
require "minitest/autorun"
require "rails/test_help"
require "devise/test/integration_helpers"

unless Object.new.respond_to?(:stub)
  class Object
    def stub(method_name, return_value = nil, callable = nil)
      value = callable || return_value

      singleton = class << self; self; end
      original_defined = singleton.method_defined?(method_name)
      original_method = singleton.instance_method(method_name) if original_defined

      singleton.define_method(method_name) do |*args, **kwargs, &block|
        if value.respond_to?(:call)
          value.call(*args, **kwargs, &block)
        else
          value
        end
      end

      yield self
    ensure
      singleton.send(:remove_method, method_name)
      if original_defined
        singleton.define_method(method_name, original_method)
      end
    end
  end
end

unless ActionController::Base.respond_to?(:impersonates)
  class << ActionController::Base
    def impersonates(*)
    end
  end
end

class ActiveSupport::TestCase
  parallelize(workers: 1)
end

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

  def create_user(name: "Test User", email: "user-#{SecureRandom.hex(4)}@example.com", password: "password123", admin: false)
    User.create!(name: name, email: email, password: password, password_confirmation: password, admin: admin)
  end

  def sign_in_as(user)
    sign_in user
  end

  def modern_headers(extra_headers = {})
    { "HTTP_USER_AGENT" => MODERN_USER_AGENT }.merge(extra_headers)
  end

  def create_workspace_with_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root = RecordingStudio::Recording.create!(recordable: workspace)
    [ workspace, root ]
  end

  def grant_root_access!(root_recording:, actor:, role: :admin)
    access = RecordingStudio::Access.create!(actor: actor, role: role)
    RecordingStudio::Recording.create!(
      recordable: access,
      root_recording: root_recording,
      parent_recording: root_recording
    )
  end
end
