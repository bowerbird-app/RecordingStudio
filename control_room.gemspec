# frozen_string_literal: true

require_relative "lib/control_room/version"

Gem::Specification.new do |spec|
  spec.name        = "control_room"
  spec.version     = ControlRoom::VERSION
  spec.authors     = ["Your Name"]
  spec.email       = ["your.email@example.com"]
  spec.homepage    = "https://github.com/bowerbird-app/control_room"
  spec.summary     = "Recordings, recordables, and event timelines for Rails"
  spec.description = "ControlRoom is a Rails engine foundation implementing Basecamp-style recordings, " \
                     "recordables, and append-only event timelines with delegated_type"
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/bowerbird-app/control_room"
  spec.metadata["changelog_uri"] = "https://github.com/bowerbird-app/control_room/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.0"
end
