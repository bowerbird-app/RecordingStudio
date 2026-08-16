# frozen_string_literal: true

require_relative "../test_helper"

class CommentableCapabilityTest < ActiveSupport::TestCase
  setup do
    ActiveRecord::Base.connection.disable_referential_integrity do
      RecordingStudio::Event.delete_all
      RecordingStudio::Recording.unscoped.delete_all
    end
    RecordingStudioComment.delete_all
    RecordingStudioPage.delete_all
    Workspace.delete_all
  end

  test "commentable page owns comment child recordables through capability enablement" do
    workspace = Workspace.create!(name: "Workspace")
    root = RecordingStudio.root_recording_for(workspace)
    page_event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "Page"),
      root_recording: root,
      parent_recording: root
    )

    assert_includes RecordingStudio.child_recordable_types_for("RecordingStudioPage"), "RecordingStudioComment"
    assert_includes RecordingStudio.allowed_parent_types_for("RecordingStudioComment"), "RecordingStudioPage"

    comment_recording = page_event.recording.comment!(body: "Looks good", actor: nil)

    assert_equal page_event.recording, comment_recording.parent_recording
    assert_equal "RecordingStudioComment", comment_recording.recordable_type
    assert_equal [ comment_recording ], page_event.recording.comments.to_a
  end
end
