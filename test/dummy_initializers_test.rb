# frozen_string_literal: true

require "test_helper"

if defined?(Turbo::StreamsChannel)
  unless Turbo::StreamsChannel.respond_to?(:broadcast_append_later_to)
    class << Turbo::StreamsChannel
      def broadcast_append_later_to(*); end
    end
  end
else
  module Turbo
    module StreamsChannel
      def self.broadcast_append_later_to(*); end
    end
  end
end

class DummyInitializersTest < ActiveSupport::TestCase
  def test_assets_initializer_adds_flat_pack_javascript_path_when_gem_is_present
    expected_path = "/tmp/fake_flat_pack/app/javascript"
    fake_spec = Struct.new(:gem_dir).new("/tmp/fake_flat_pack")

    Gem::Specification.stub(:find_by_name, ->(_name) { fake_spec }) do
      load dummy_initializer_path("assets")
    end

    assert_includes Rails.application.config.assets.paths.map(&:to_s), expected_path
  ensure
    Rails.application.config.assets.paths.delete(expected_path)
  end

  def test_assets_initializer_handles_missing_flat_pack_gem
    Gem::Specification.stub(:find_by_name, ->(_name) { raise Gem::LoadError }) do
      load dummy_initializer_path("assets")
    end

    assert true
  end

  def test_flatpack_initializer_calls_configure_when_available
    calls = 0
    flatpack_singleton = class << FlatPack
                           self
                         end

    flatpack_singleton.send(:define_method, :configure) do |&block|
      calls += 1
      block&.call(Object.new)
    end

    load dummy_initializer_path("flatpack")

    assert_equal 1, calls
  ensure
    flatpack_singleton.send(:remove_method, :configure) if FlatPack.respond_to?(:configure)
  end

  def test_notifications_initializer_broadcasts_impersonator_message
    calls = []

    Turbo::StreamsChannel.stub(:broadcast_append_later_to, lambda { |*args, **kwargs|
      calls << { args: args, kwargs: kwargs }
    }) do
      load dummy_initializer_path("recording_studio_notifications")

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

    assert_not_nil matching_call
  end

  def test_notifications_initializer_uses_default_message_values
    calls = []

    Turbo::StreamsChannel.stub(:broadcast_append_later_to, lambda { |*args, **kwargs|
      calls << { args: args, kwargs: kwargs }
    }) do
      load dummy_initializer_path("recording_studio_notifications")
      ActiveSupport::Notifications.instrument("recordings.event_created", {})
    end

    matching_call = calls.find do |call|
      locals = call[:kwargs][:locals] || {}
      locals[:body] == "Recordable updated by System"
    end

    assert_not_nil matching_call
  end

  private

  def dummy_initializer_path(name)
    Rails.root.join("config/initializers/#{name}.rb")
  end
end
