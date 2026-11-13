# frozen_string_literal: true

require "test_helper"

class EngineExtensionReloadTest < ActiveSupport::TestCase
  def test_model_and_controller_extensions_reapply_after_reload_but_not_twice
    configuration = RecordingStudio.configuration
    original_hooks = configuration.instance_variable_get(:@hooks)
    configuration.instance_variable_set(:@hooks, RecordingStudio::Hooks.new)
    model_runs = []
    controller_runs = []

    configuration.hooks.extend_model(:recording) do
      model_runs << self
      def reloaded_model_extension
        :applied
      end
    end
    configuration.hooks.extend_controller(:application) do
      controller_runs << self
      def reloaded_controller_extension
        :applied
      end
    end

    originals = {
      Recording: RecordingStudio::Recording,
      ApplicationController: RecordingStudio::ApplicationController
    }
    first_recording = swap_reload_stand_in(:Recording)
    first_controller = swap_reload_stand_in(:ApplicationController)

    2.times { RecordingStudio::Engine.apply_registered_extensions! }

    assert_equal [first_recording], model_runs
    assert_equal [first_controller], controller_runs
    assert_equal :applied, first_recording.new.reloaded_model_extension
    assert_equal :applied, first_controller.new.reloaded_controller_extension

    reloaded_recording = swap_reload_stand_in(:Recording)
    reloaded_controller = swap_reload_stand_in(:ApplicationController)
    assert_equal "RecordingStudio::Recording", reloaded_recording.name
    assert_equal "RecordingStudio::ApplicationController", reloaded_controller.name
    refute_equal first_recording.object_id, reloaded_recording.object_id
    refute_equal first_controller.object_id, reloaded_controller.object_id

    2.times { RecordingStudio::Engine.apply_registered_extensions! }

    assert_equal [first_recording, reloaded_recording], model_runs
    assert_equal [first_controller, reloaded_controller], controller_runs
    assert_equal :applied, reloaded_recording.new.reloaded_model_extension
    assert_equal :applied, reloaded_controller.new.reloaded_controller_extension
    refute_extension_keys_hold(reloaded_recording, reloaded_controller)
  ensure
    configuration&.instance_variable_set(:@hooks, original_hooks) if original_hooks
    restore_reload_constants(originals) if originals
  end

  private

  def swap_reload_stand_in(name)
    RecordingStudio.send(:remove_const, name)
    RecordingStudio.const_set(name, Class.new)
  end

  def restore_reload_constants(originals)
    originals.each do |name, klass|
      RecordingStudio.send(:remove_const, name) if RecordingStudio.const_defined?(name, false)
      RecordingStudio.const_set(name, klass)
    end
  end

  def refute_extension_keys_hold(*classes)
    RecordingStudio::Engine.applied_extension_keys.each do |key|
      key.each do |part|
        classes.each do |klass|
          refute_equal klass, part
        end
      end
    end
  end
end
