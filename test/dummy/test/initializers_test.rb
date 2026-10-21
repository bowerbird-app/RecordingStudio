# frozen_string_literal: true

require_relative "test_helper"

unless defined?(Turbo::StreamsChannel)
  module Turbo
    module StreamsChannel
      def self.broadcast_append_later_to(*)
      end
    end
  end
else
  unless Turbo::StreamsChannel.respond_to?(:broadcast_append_later_to)
    class << Turbo::StreamsChannel
      def broadcast_append_later_to(*)
      end
    end
  end
end

class InitializersTest < Minitest::Test
  def test_assets_initializer_adds_dummy_builds_path
    expected_path = Rails.root.join("app/assets/builds").to_s

    load initializer_path("assets")

    assert_includes Rails.application.config.assets.paths.map(&:to_s), expected_path
  ensure
    restore_builds_asset_path!
  end

  def test_assets_initializer_is_idempotent_for_dummy_builds_path
    expected_path = Rails.root.join("app/assets/builds")

    Rails.application.config.assets.paths.delete(expected_path)
    2.times { load initializer_path("assets") }

    matching_paths = Rails.application.config.assets.paths.count { |path| path == expected_path }

    assert_equal 1, matching_paths
  ensure
    restore_builds_asset_path!
  end

  def test_flatpack_initializer_calls_configure_when_available
    calls = 0
    flatpack_singleton = class << FlatPack
      self
    end

    flatpack_singleton.send(:define_method, :configure) do |&block|
      calls += 1
      block.call(Object.new) if block
    end

    load initializer_path("flatpack")

    assert_equal 1, calls
  ensure
    flatpack_singleton.send(:remove_method, :configure) if FlatPack.respond_to?(:configure)
  end

  def test_notifications_initializer_broadcasts_impersonator_message
    calls = []

    Turbo::StreamsChannel.stub(:broadcast_append_later_to, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
      load initializer_path("recording_studio_notifications")

      ActiveSupport::Notifications.instrument(
        "recordings.event_created",
        actor_type: "User",
        actor_id: "42",
        impersonator_type: "Admin",
        impersonator_id: "7",
        recordable_type: "RecordingStudioPage",
        action: "created"
      )
    end

    matching_call = calls.find do |call|
      kwargs = call[:kwargs]
      locals = kwargs[:locals] || {}

      call[:args].first == "recording_studio_toasts" &&
        kwargs[:target] == "toast-container" &&
        kwargs[:partial] == "toasts/toast" &&
        locals[:title] == "Rails notification: recordings.event_created" &&
        locals[:body] == "RecordingStudioPage created by User#42 (impersonated by Admin#7)"
    end

    refute_nil matching_call
  end

  def test_notifications_initializer_uses_default_message_values
    calls = []

    Turbo::StreamsChannel.stub(:broadcast_append_later_to, ->(*args, **kwargs) { calls << { args: args, kwargs: kwargs } }) do
      load initializer_path("recording_studio_notifications")
      ActiveSupport::Notifications.instrument("recordings.event_created", {})
    end

    matching_call = calls.find do |call|
      locals = call[:kwargs][:locals] || {}
      locals[:body] == "Recordable updated by System"
    end

    refute_nil matching_call
  end

  def test_engine_application_controller_uses_the_shared_layout_macro
    assert_includes ActionController::Base.included_modules, RecordingStudio::ControllerLayout
    assert_respond_to RecordingStudio::ApplicationController, :recording_studio_layout

    original = RecordingStudio.configuration.layout
    RecordingStudio.configuration.layout = nil
    resolved = RecordingStudio::ApplicationController.new.send(:recording_studio_resolved_layout)

    assert_equal RecordingStudio::DEFAULT_LAYOUT, resolved
  ensure
    RecordingStudio.configuration.layout = original if defined?(original)
  end

  private

  def initializer_path(name)
    Rails.root.join("config/initializers/#{name}.rb")
  end

  # These tests temporarily mutate global asset paths; always leave builds on the
  # load path so later integration renders (layout_demo, etc.) can find tailwind.css.
  def restore_builds_asset_path!
    expected = Rails.root.join("app/assets/builds")
    paths = Rails.application.config.assets.paths
    paths.reject! { |path| path.to_s == expected.to_s }
    paths << expected
  end
end
