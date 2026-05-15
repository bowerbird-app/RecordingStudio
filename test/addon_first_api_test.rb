# frozen_string_literal: true

require "test_helper"

class AddonFirstApiTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    @original_dup_strategy = RecordingStudio.configuration.recordable_dup_strategy
    @original_dup_strategies = RecordingStudio.configuration.recordable_dup_strategies.dup
    @original_label_formatters = RecordingStudio::Labels.formatters.transform_values(&:dup)

    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio.configuration.recordable_dup_strategy = :dup
    RecordingStudio.configuration.recordable_dup_strategies.clear
    reset_label_formatters!
    RecordingStudio::DelegatedTypeRegistrar.apply!

    reset_recording_studio_tables!(RecordingStudioPage)
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio.configuration.recordable_dup_strategy = @original_dup_strategy
    RecordingStudio.configuration.recordable_dup_strategies.clear
    RecordingStudio.configuration.recordable_dup_strategies.merge!(@original_dup_strategies)
    reset_label_formatters!(@original_label_formatters)
  end

  def test_recording_exposes_identity_helpers
    _workspace, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    assert_equal "RecordingStudioPage", recording.recordable_type_name
    assert_equal recording.recordable_id, recording.recordable_identifier
    assert_equal recording.recordable.to_global_id.to_s, recording.recordable_global_id
  end

  def test_recording_exposes_tree_helpers
    _workspace, root_recording = create_workspace_root
    parent = root_recording.record(RecordingStudioPage) { |page| page.title = "Parent" }
    child = root_recording.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = "Child" }

    assert_respond_to child, :root?
    assert_respond_to child, :leaf?
    assert_respond_to child, :depth
    assert_respond_to child, :level
    assert_respond_to child, :ancestors
    assert_respond_to child, :self_and_ancestors
    assert_respond_to parent, :descendants
    assert_respond_to parent, :self_and_descendants
    assert_respond_to parent, :descendant_ids
    assert_respond_to parent, :subtree_recordings

    assert_equal [root_recording, parent], child.ancestors
    assert_equal [child], parent.descendants
    assert_equal [child.id], parent.descendant_ids
    assert_equal [parent.id, child.id], parent.subtree_recordings.map(&:id)
    assert_equal 2, child.depth
    assert child.leaf?
  end

  def test_recording_class_exposes_deterministic_locking_helper
    _workspace, root_recording = create_workspace_root
    first = root_recording.record(RecordingStudioPage) { |page| page.title = "First" }
    second = root_recording.record(RecordingStudioPage) { |page| page.title = "Second" }

    RecordingStudio::Recording.transaction do
      locked = RecordingStudio::Recording.lock_ids!([second.id, first.id, second.id])

      assert_equal [first.id, second.id].sort, locked.map(&:id)
    end
  end

  def test_core_helpers_cover_identity_and_root_relationships
    _workspace, root_recording = create_workspace_root
    local_recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Local" }
    _other_workspace, other_root = create_workspace_root(name: "Other")
    foreign_recording = other_root.record(RecordingStudioPage) { |page| page.title = "Foreign" }

    assert_equal "Workspace", RecordingStudio.recordable_type_name(Workspace)
    assert_equal Workspace, RecordingStudio.resolve_recordable_type("Workspace")
    assert_equal local_recording.recordable_id, RecordingStudio.recordable_identifier(local_recording.recordable)
    assert_equal "Local", RecordingStudio.recordable_name(local_recording.recordable)
    assert_equal "Page", RecordingStudio.recordable_type_label(local_recording.recordable)
    assert_equal root_recording, RecordingStudio.root_recording_or_self(local_recording)
    assert_equal root_recording.id, RecordingStudio.root_recording_id_for(local_recording)

    assert_nothing_raised do
      RecordingStudio.assert_recording_belongs_to_root!(root_recording, local_recording)
    end

    assert_raises(ArgumentError) do
      RecordingStudio.assert_recording_belongs_to_root!(root_recording, foreign_recording)
    end
  end

  def test_root_recording_for_finds_or_creates_root_recording
    workspace = Workspace.create!(name: "Workspace")

    root_recording = RecordingStudio.root_recording_for(workspace)

    assert_predicate root_recording, :persisted?
    assert_equal workspace, root_recording.recordable
    assert RecordingStudio.root_recording?(root_recording)
    assert_equal root_recording, RecordingStudio.root_recording_for(workspace)
  end

  def test_record_bang_infers_root_recording_from_recording
    _workspace, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    event = RecordingStudio.record!(
      action: "reviewed",
      recordable: recording.recordable,
      recording: recording
    )

    assert_equal recording, event.recording
    assert_equal root_recording, event.recording.root_recording
  end

  def test_record_bang_rejects_non_root_root_recording
    _workspace, root_recording = create_workspace_root
    child_recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Child" }

    error = assert_raises(ArgumentError) do
      RecordingStudio.record!(
        action: "created",
        recordable: RecordingStudioPage.new(title: "Invalid"),
        root_recording: child_recording
      )
    end

    assert_equal "root_recording must be a root recording", error.message
  end

  def test_configuration_supports_per_type_duplication_strategies
    _workspace, root_recording = create_workspace_root
    recording = root_recording.record(RecordingStudioPage) { |page| page.title = "Draft" }

    RecordingStudio.configuration.register_recordable_dup_strategy("RecordingStudioPage") do |recordable|
      RecordingStudioPage.new(title: "Addon #{recordable.title}")
    end

    revised = root_recording.revise(recording)

    assert_equal "Addon Draft", revised.recordable.title
    assert_respond_to RecordingStudio.dup_strategy_for(RecordingStudioPage), :call
  end

  def test_default_duplication_helper_resets_counter_caches
    recordable = RecordingStudioPage.new(title: "Draft", recordings_count: 4, events_count: 2)

    duplicated = RecordingStudio::Duplication.reset_counter_caches(recordable.dup)

    assert_equal 0, duplicated.recordings_count
    assert_equal 0, duplicated.events_count
  end

  def test_labels_support_registered_addon_formatters
    recordable = RecordingStudioPage.new(title: "Draft")

    RecordingStudio::Labels.register_formatter(
      RecordingStudioPage,
      name: ->(page) { "Addon #{page.title}" },
      type_label: ->(_page) { "Addon Page" },
      title: ->(_page) { "Addon Title" },
      summary: ->(_page) { "Addon Summary" }
    )

    assert_equal "Addon Draft", RecordingStudio::Labels.name_for(recordable)
    assert_equal "Addon Page", RecordingStudio::Labels.type_label_for(recordable)
    assert_equal "Addon Title", RecordingStudio::Labels.title_for(recordable)
    assert_equal "Addon Summary", RecordingStudio::Labels.summary_for(recordable)
  end

  private

  def create_workspace_root(name: "Workspace")
    workspace = Workspace.create!(name: name)
    root_recording = RecordingStudio::Recording.create!(recordable: workspace)
    [workspace, root_recording]
  end

  def reset_label_formatters!(formatters = nil)
    defaults = RecordingStudio::Labels::FORMATTER_TYPES.index_with { {} }
    RecordingStudio::Labels.instance_variable_set(:@formatters, defaults)
    return if formatters.nil?

    RecordingStudio::Labels.formatters.each_key do |kind|
      RecordingStudio::Labels.formatters[kind].merge!(formatters.fetch(kind, {}))
    end
  end
end
