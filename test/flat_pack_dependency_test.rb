# frozen_string_literal: true

require "test_helper"

class FlatPackDependencyTest < ActiveSupport::TestCase
  test "gemspec requires flat_pack 0.1.315 or newer" do
    spec = Gem::Specification.load(RecordingStudio::Engine.root.join("recording_studio.gemspec").to_s)
    requirement = spec.dependencies.find { |dependency| dependency.name == "flat_pack" }.requirement

    assert requirement.satisfied_by?(Gem::Version.new("0.1.315"))
    refute requirement.satisfied_by?(Gem::Version.new("0.1.314"))
  end

  test "development gemfiles pin flat_pack release tags" do
    root = RecordingStudio::Engine.root

    assert_includes File.read(root.join("Gemfile")), 'tag: "v0.2.0"'
    assert_includes File.read(root.join("test/dummy/Gemfile")), 'tag: "v0.2.0"'
  end

  test "resolved flat_pack and view_component match this checkout" do
    root = RecordingStudio::Engine.root

    assert_equal "7.9.1", RecordingStudio::VERSION
    assert_includes File.read(root.join("Gemfile.lock")), "recording_studio (#{RecordingStudio::VERSION})"
    assert_includes File.read(root.join("test/dummy/Gemfile.lock")), "recording_studio (#{RecordingStudio::VERSION})"
    assert_equal "0.2.0", FlatPack::VERSION
    assert_equal "4.19.0", ViewComponent::VERSION::STRING

    source = RecordingStudio::Engine.root.join("app").to_s
    app_files = Dir.glob(File.join(source, "**", "*.{rb,erb}"))
    app_files.each do |path|
      refute_includes File.read(path), "ViewComponent::ExperimentallyCacheable"
    end
  end
end
