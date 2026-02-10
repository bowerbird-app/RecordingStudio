# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/test/"
end

ENV["RAILS_ENV"] ||= "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)

require "minitest/autorun"
require "rails"

module FlatPack
  class Engine < ::Rails::Engine; end
end

require File.expand_path("dummy/config/environment", __dir__)
require "rails/test_help"
require "recording_studio"

Rails.application.config.hosts.clear
Rails.application.config.hosts << "example.com"
Rails.application.config.hosts << "www.example.com"
