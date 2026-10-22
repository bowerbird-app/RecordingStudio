# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in recording_studio.gemspec
gemspec

gem "puma"
gem "sprockets-rails"

# flat_pack is not published on RubyGems. The gemspec depends on it; this line is the git source.
gem "flat_pack", git: "https://github.com/bowerbird-app/flatpack.git", tag: "v0.1.296"

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
  gem "pretender"
  gem "simplecov", require: false
end
