# frozen_string_literal: true

require "test_helper"

class HardeningApiTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_require_actor = RecordingStudio.configuration.require_actor
    @original_authorize = RecordingStudio.configuration.authorize_write
    @original_max_metadata = RecordingStudio.configuration.max_metadata_bytes
    @original_unsafe = RecordingStudio.configuration.allow_unsafe_recordable_queries
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.require_actor = @original_require_actor
    RecordingStudio.configuration.authorize_write = @original_authorize
    RecordingStudio.configuration.max_metadata_bytes = @original_max_metadata
    RecordingStudio.configuration.allow_unsafe_recordable_queries = @original_unsafe
    RecordingStudio.configuration.hooks.clear(:before_record)
    RecordingStudio.configuration.hooks.clear(:after_record)
  end

  def test_events_are_append_only
    _, root = create_workspace_root
    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root,
      parent_recording: root
    )

    assert_raises(ActiveRecord::ReadOnlyRecord) { event.update!(action: "tampered") }
    assert_raises(ActiveRecord::ReadOnlyRecord) { event.destroy! }
  end

  def test_revert_rejects_foreign_snapshot
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "Original" }
    foreign = RecordingStudioPage.create!(title: "Foreign")

    assert_raises(RecordingStudio::InvalidRevertTarget) do
      root.revert(recording, to_recordable: foreign)
    end
  end

  def test_revert_accepts_historical_snapshot
    _, root = create_workspace_root
    recording = root.record(RecordingStudioPage) { |page| page.title = "Original" }
    original = recording.recordable
    root.revise(recording) { |page| page.title = "Updated" }

    reverted = root.revert(recording, to_recordable: original)

    assert_equal original.id, reverted.recordable_id
  end

  def test_require_actor_blocks_missing_actor
    RecordingStudio.configuration.require_actor = true
    _, root = create_workspace_root

    assert_raises(RecordingStudio::ActorRequired) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "One"),
        root_recording: root,
        parent_recording: root,
        actor: nil
      )
    end
  end

  def test_authorize_write_can_deny
    RecordingStudio.configuration.authorize_write = ->(**) { false }
    _, root = create_workspace_root

    assert_raises(RecordingStudio::AuthorizationError) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "One"),
        root_recording: root,
        parent_recording: root
      )
    end
  end

  def test_metadata_size_limit
    RecordingStudio.configuration.max_metadata_bytes = 32
    _, root = create_workspace_root

    assert_raises(RecordingStudio::MetadataTooLarge) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "One"),
        root_recording: root,
        parent_recording: root,
        metadata: { note: "x" * 100 }
      )
    end
  end

  def test_unsafe_recordable_scope_requires_opt_in
    _, root = create_workspace_root
    root.record(RecordingStudioPage) { |page| page.title = "Alpha" }

    assert_raises(RecordingStudio::UnsafeRecordableQuery) do
      root.recordings_query(
        include_children: true,
        type: RecordingStudioPage,
        recordable_scope: ->(scope) { scope.where(recording_studio_pages: { title: "Alpha" }) }
      ).to_a
    end
  end

  def test_record_hooks_fire
    before_payloads = []
    after_events = []
    RecordingStudio.configuration.hooks.before_record { |payload| before_payloads << payload }
    RecordingStudio.configuration.hooks.after_record { |event| after_events << event }

    _, root = create_workspace_root
    event = RecordingStudio.record!(
      action: "created",
      recordable: RecordingStudioPage.new(title: "One"),
      root_recording: root,
      parent_recording: root
    )

    assert_equal 1, before_payloads.size
    assert_equal "created", before_payloads.first[:action]
    assert_equal [event.id], after_events.map(&:id)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    [workspace, RecordingStudio.root_recording_for(workspace)]
  end
end
