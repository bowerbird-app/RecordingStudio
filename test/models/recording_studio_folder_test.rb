# frozen_string_literal: true

require "test_helper"

class RecordingStudioFolderTest < ActiveSupport::TestCase
  def test_folder_requires_name
    folder = RecordingStudioFolder.new(name: nil)

    assert_not folder.valid?
    assert_includes folder.errors[:name], "can't be blank"
  end

  def test_folder_can_be_registered_and_recorded
    original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioFolder]
    RecordingStudio::DelegatedTypeRegistrar.apply!

    workspace = Workspace.create!(name: "Folder Workspace")
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)

    folder_recording = root_recording.record(RecordingStudioFolder) do |folder|
      folder.name = "Projects"
    end

    assert_equal "RecordingStudioFolder", folder_recording.recordable_type
    assert_equal "Projects", folder_recording.recordable.name
  ensure
    RecordingStudio.configuration.recordable_types = original_types
    RecordingStudio::DelegatedTypeRegistrar.apply!
  end
end
