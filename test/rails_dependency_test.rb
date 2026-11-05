# frozen_string_literal: true

require "test_helper"

class RailsDependencyTest < ActiveSupport::TestCase
  test "gemspec requires rails 8.1.4.1 or newer" do
    spec = Gem::Specification.load(RecordingStudio::Engine.root.join("recording_studio.gemspec").to_s)
    requirement = spec.dependencies.find { |dependency| dependency.name == "rails" }.requirement

    assert requirement.satisfied_by?(Gem::Version.new("8.1.4.1"))
    refute requirement.satisfied_by?(Gem::Version.new("8.1.4"))
  end
end
