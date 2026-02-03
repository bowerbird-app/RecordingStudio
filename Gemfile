# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio.gemspec
gemspec

gem "puma"
gem "sprockets-rails"

group :development, :test do
  gem "bootsnap", require: false
  gem "debug"
  gem "pg", "~> 1.1"
end

group :development do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false
end

group :test do
  gem "devise"
  gem "simplecov", require: false
end
