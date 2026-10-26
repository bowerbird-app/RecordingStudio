# frozen_string_literal: true

require "test_helper"

class FlatPackDependencyTest < ActiveSupport::TestCase
  test "gemspec requires flat_pack 0.1.313 or newer" do
    spec = Gem::Specification.load(RecordingStudio::Engine.root.join("recording_studio.gemspec").to_s)
    requirement = spec.dependencies.find { |dependency| dependency.name == "flat_pack" }.requirement

    assert requirement.satisfied_by?(Gem::Version.new("0.1.313"))
    refute requirement.satisfied_by?(Gem::Version.new("0.1.312"))
  end

  test "development gemfiles pin flat_pack tag v0.1.313" do
    root = RecordingStudio::Engine.root

    [root.join("Gemfile"), root.join("test/dummy/Gemfile")].each do |gemfile|
      assert_includes File.read(gemfile), 'tag: "v0.1.313"'
    end
  end

  test "resolved flat_pack and view_component match the 6.0.3 release" do
    assert_equal "6.0.3", RecordingStudio::VERSION
    assert_equal "0.1.313", FlatPack::VERSION
    assert_equal "4.19.0", ViewComponent::VERSION::STRING

    source = RecordingStudio::Engine.root.join("app").to_s
    app_files = Dir.glob(File.join(source, "**", "*.{rb,erb}"))
    app_files.each do |path|
      refute_includes File.read(path), "ViewComponent::ExperimentallyCacheable"
    end
  end
end
