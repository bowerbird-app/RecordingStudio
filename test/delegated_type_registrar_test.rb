# frozen_string_literal: true

require "test_helper"

class DelegatedTypeRegistrarTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_apply_adds_delegated_type_association
    RecordingStudio.configuration.recordable_types = ["RecordingStudioPage"]

    RecordingStudio::DelegatedTypeRegistrar.apply!

    assert RecordingStudio::Recording.reflect_on_association(:recordable)
  end

  def test_apply_includes_recordable_concern
    RecordingStudio.configuration.recordable_types = ["RecordingStudioPage"]

    RecordingStudio::DelegatedTypeRegistrar.apply!

    assert RecordingStudioPage.included_modules.include?(RecordingStudio::Recordable)
  end

  def test_apply_is_idempotent_for_same_types
    RecordingStudio.configuration.recordable_types = ["RecordingStudioPage"]

    RecordingStudio::DelegatedTypeRegistrar.apply!
    first_types = RecordingStudio::Recording.instance_variable_get(:@recording_studio_recordable_types)

    RecordingStudio::DelegatedTypeRegistrar.apply!
    second_types = RecordingStudio::Recording.instance_variable_get(:@recording_studio_recordable_types)

    assert_equal first_types, second_types
  end

  def test_apply_skips_non_active_record_classes
    RecordingStudio.configuration.recordable_types = ["String"]

    RecordingStudio::DelegatedTypeRegistrar.apply!

    refute String.included_modules.include?(RecordingStudio::Recordable)
  end
end
