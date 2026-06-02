# frozen_string_literal: true

require "test_helper"

class DelegatedTypeRegistrarTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_require_declarations = RecordingStudio.configuration.require_recordable_declarations
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.require_recordable_declarations = @original_require_declarations
  end

  def test_apply_adds_delegated_type_association
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]

    RecordingStudio::DelegatedTypeRegistrar.apply!

    assert RecordingStudio::Recording.reflect_on_association(:recordable)
  end

  def test_apply_includes_recordable_concern
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]

    RecordingStudio::DelegatedTypeRegistrar.apply!

    assert RecordingStudioPage.included_modules.include?(RecordingStudio::Recordable)
  end

  def test_apply_is_idempotent_for_same_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]

    RecordingStudio::DelegatedTypeRegistrar.apply!
    first_types = RecordingStudio::Recording.instance_variable_get(:@recording_studio_recordable_types)

    RecordingStudio::DelegatedTypeRegistrar.apply!
    second_types = RecordingStudio::Recording.instance_variable_get(:@recording_studio_recordable_types)

    assert_equal first_types, second_types
  end

  def test_apply_skips_non_active_record_classes
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
      String
    ]
    RecordingStudio.configuration.require_recordable_declarations = false

    RecordingStudio::DelegatedTypeRegistrar.apply!

    assert_not String.included_modules.include?(RecordingStudio::Recordable)
  end

  def test_apply_defers_missing_declaration_validation_until_app_finishes_initializing
    RecordingStudio.configuration.recordable_types = ["BootOnlyType"]

    app = Rails.application
    original_initialized = app.method(:initialized?)
    app.singleton_class.send(:define_method, :initialized?) { false }

    RecordingStudio::DelegatedTypeRegistrar.apply!

    app.singleton_class.send(:define_method, :initialized?) { true }

    assert_raises(RecordingStudio::MissingRecordableDeclaration) do
      RecordingStudio::DelegatedTypeRegistrar.apply!
    end
  ensure
    app.singleton_class.send(:define_method, :initialized?, original_initialized)
  end
end
