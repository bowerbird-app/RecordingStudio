# frozen_string_literal: true

require "test_helper"

class RecordingFiltersTest < ActiveSupport::TestCase
  def setup
    @original_types = RecordingStudio.configuration.recordable_types
    RecordingStudio.configuration.recordable_types = %w[
      Workspace
      RecordingStudioPage
      RecordingStudioComment
      RecordingStudioFolder
    ]
    RecordingStudio::DelegatedTypeRegistrar.apply!
    RecordingStudio::RecordingFilters.reset!
    reset_recording_studio_tables!(RecordingStudioFolder, RecordingStudioPage, RecordingStudioComment)
  end

  def teardown
    RecordingStudio::RecordingFilters.reset!
    RecordingStudio.configuration.recordable_types = @original_types
  end

  def test_kept_returns_every_recording_when_no_filter_is_registered
    root = create_workspace_root
    page = record_page(root, "Draft")

    assert_equal "1=1", RecordingStudio.kept_sql
    assert_equal "1=1", RecordingStudio.kept_sql("parents")
    assert_equal RecordingStudio::Recording.all.order(:id).pluck(:id),
                 RecordingStudio::Recording.kept.order(:id).pluck(:id)
    assert_includes RecordingStudio::Recording.kept, root
    assert_includes RecordingStudio::Recording.kept, page
    assert_empty RecordingStudio::Recording.default_scopes
  end

  def test_kept_applies_each_registered_filter_in_registration_order
    root = create_workspace_root
    page = record_page(root, "Draft")
    register_type_filter(:kind, "Workspace")
    register_parent_filter(:roots)

    assert_equal [root.id], RecordingStudio::Recording.kept.order(:id).pluck(:id)
    assert_equal [root.id], RecordingStudio::Recording.where(recordable_type: "Workspace").kept.pluck(:id)
    assert_empty RecordingStudio::Recording.where(recordable_type: "RecordingStudioPage").kept
    assert_equal [root.id], RecordingStudio::Recording.where(RecordingStudio.kept_sql).order(:id).pluck(:id)
    refute_includes RecordingStudio::Recording.kept, page
    assert_equal kept_sql("Workspace", "parent_recording_id IS NULL"), RecordingStudio.kept_sql
    assert_includes root.subtree_recordings, page
    assert_includes root.descendants, page
    assert_includes RecordingStudio::Recording.all, page
    assert_equal [page.id], RecordingStudio::Recording.lock_ids!([page.id]).pluck(:id)
  end

  def test_reregistering_the_same_name_replaces_the_filter_in_place
    root = create_workspace_root
    page = record_page(root, "Draft")
    register_type_filter(:kind, "Workspace")
    register_parent_filter(:roots)
    register_type_filter(:kind, "RecordingStudioPage")

    assert_empty RecordingStudio::Recording.kept
    assert_equal kept_sql("RecordingStudioPage", "parent_recording_id IS NULL"), RecordingStudio.kept_sql
    assert_equal 1, RecordingStudio.kept_sql.scan("recordable_type").size
    refute_includes RecordingStudio::Recording.kept, root
    refute_includes RecordingStudio::Recording.kept, page

    assert RecordingStudio.unregister_recording_filter(:roots)
    assert_equal [page.id], RecordingStudio::Recording.kept.order(:id).pluck(:id)
    assert_equal false, RecordingStudio.unregister_recording_filter(:roots)
    assert_equal false, RecordingStudio.unregister_recording_filter("missing")
  end

  def test_string_and_symbol_names_share_one_registration
    register_type_filter("kind", "Workspace")
    register_type_filter(:kind, "RecordingStudioPage")

    assert_equal 1, RecordingStudio.kept_sql.scan("recordable_type").size
    assert_includes RecordingStudio.kept_sql, "RecordingStudioPage"
    refute_includes RecordingStudio.kept_sql, "Workspace"
  end

  def test_kept_sql_quotes_the_default_table_and_a_join_alias
    root = create_workspace_root
    direct = record_page(root, "Direct")
    nested = record_page(root, "Nested", parent: direct)
    register_type_filter(:kind, "Workspace")

    quoted_recordings = quote_identifier("recording_studio_recordings")
    quoted_parents = quote_identifier("parents")
    assert_equal "(#{quoted_recordings}.recordable_type = 'Workspace')", RecordingStudio.kept_sql
    assert_equal "(#{quoted_parents}.recordable_type = 'Workspace')", RecordingStudio.kept_sql("parents")
    assert_equal "(#{quoted_parents}.recordable_type = 'Workspace')", RecordingStudio.kept_sql(:parents)

    ids = RecordingStudio::Recording.connection.select_values(<<~SQL.squish)
      SELECT children.id::text
      FROM recording_studio_recordings children
      INNER JOIN recording_studio_recordings parents
        ON parents.id = children.parent_recording_id
      WHERE #{RecordingStudio.kept_sql('parents')}
    SQL

    assert_includes ids, direct.id
    refute_includes ids, nested.id
    refute_includes ids, root.id
  end

  def test_registry_still_filters_after_code_reload
    root = create_workspace_root
    page = record_page(root, "Draft")
    register_type_filter(:kind, "RecordingStudioPage")
    registry = RecordingStudio::RecordingFilters

    Rails.application.reloader.reload!

    assert_same registry, RecordingStudio::RecordingFilters
    assert_equal [page.id], RecordingStudio::Recording.kept.order(:id).pluck(:id)
    refute_includes RecordingStudio::Recording.kept, root
    assert_includes root.subtree_recordings, root
    assert_includes root.subtree_recordings, page
  end

  def test_registration_rejects_a_missing_block_or_sql_callable
    error = assert_raises(ArgumentError) do
      RecordingStudio.register_recording_filter(:kind, sql: ->(table) { "#{table}.id IS NOT NULL" })
    end
    assert_equal "recording filter requires a block", error.message

    error = assert_raises(ArgumentError) do
      RecordingStudio.register_recording_filter(:kind, sql: "trashed_at IS NULL") { |recordings| recordings }
    end
    assert_equal "recording filter sql must respond to call", error.message

    error = assert_raises(ArgumentError) do
      RecordingStudio.register_recording_filter("", sql: ->(*) { "1=1" }) { |recordings| recordings }
    end
    assert_equal "recording filter name must be a non-empty string or symbol", error.message

    error = assert_raises(ArgumentError) do
      RecordingStudio.register_recording_filter(1, sql: ->(*) { "1=1" }) { |recordings| recordings }
    end
    assert_equal "recording filter name must be a non-empty string or symbol", error.message
  end

  def test_kept_rejects_a_filter_that_does_not_return_a_relation_or_sql
    RecordingStudio.register_recording_filter(:kind, sql: ->(table) { "#{table}.id IS NOT NULL" }) { |_recordings| nil }
    error = assert_raises(ArgumentError) { RecordingStudio::Recording.kept.to_sql }
    assert_equal "recording filter :kind must return a relation", error.message

    RecordingStudio.register_recording_filter(:kind, sql: ->(*) {}) { |recordings| recordings }
    error = assert_raises(ArgumentError) { RecordingStudio.kept_sql }
    assert_equal "recording filter :kind sql must return a SQL string", error.message

    RecordingStudio.register_recording_filter(:kind, sql: ->(*) { "   " }) { |recordings| recordings }
    error = assert_raises(ArgumentError) { RecordingStudio.kept_sql }
    assert_equal "recording filter :kind sql must return a SQL string", error.message
  end

  def test_kept_sql_rejects_an_unsafe_table_identifier
    ["parents;drop", "parents.recordable_type", "\"parents\"", "", "1parents", "a" * 64].each do |table|
      assert_raises(ArgumentError) { RecordingStudio.kept_sql(table) }
    end
    assert_raises(ArgumentError) { RecordingStudio.kept_sql(nil) }
  end

  def test_concurrent_registration_keeps_every_name
    threads = Array.new(8) do |index|
      Thread.new do
        RecordingStudio.register_recording_filter(
          :"filter_#{index}",
          sql: ->(table) { "#{table}.recordable_type <> 'filter_#{index}'" }
        ) { |recordings| recordings.where.not(recordable_type: "filter_#{index}") }
      end
    end
    threads.each(&:join)

    sql = RecordingStudio.kept_sql
    8.times { |index| assert_includes sql, "filter_#{index}" }
    assert_equal 7, sql.scan(" AND ").size
  end

  private

  def create_workspace_root
    RecordingStudio.root_recording_for(Workspace.create!(name: "Workspace"))
  end

  def record_page(root, title, parent: root)
    root.record(RecordingStudioPage, parent_recording: parent) { |page| page.title = title }
  end

  def register_type_filter(name, type_name)
    RecordingStudio.register_recording_filter(
      name,
      sql: ->(table) { "#{table}.recordable_type = '#{type_name}'" }
    ) { |recordings| recordings.where(recordable_type: type_name) }
  end

  def register_parent_filter(name)
    RecordingStudio.register_recording_filter(
      name,
      sql: ->(table) { "#{table}.parent_recording_id IS NULL" }
    ) { |recordings| recordings.where(parent_recording_id: nil) }
  end

  def kept_sql(type_name, second_fragment)
    quoted = quote_identifier("recording_studio_recordings")
    "(#{quoted}.recordable_type = '#{type_name}') AND (#{quoted}.#{second_fragment})"
  end

  def quote_identifier(identifier)
    RecordingStudio::Recording.connection.quote_table_name(identifier)
  end
end
