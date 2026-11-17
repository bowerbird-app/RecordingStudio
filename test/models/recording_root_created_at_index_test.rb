# frozen_string_literal: true

require "test_helper"

class RecordingRootCreatedAtIndexTest < ActiveSupport::TestCase
  MIGRATION = "20261117200000_replace_recording_studio_recordings_root_index.rb"

  def test_install_and_upgrade_migrations_match
    root = RecordingStudio::Engine.root

    assert_equal File.read(root.join("db/migrate", MIGRATION)),
                 File.read(root.join("db/install_migrate", MIGRATION))
  end

  def test_root_created_at_index_orders_created_at_and_id_newest_first_with_no_where
    index = index_named("index_rs_recordings_on_root_created_at_id")
    type_page = index_named("index_rs_recordings_on_root_type_created_at_id")

    assert index
    assert_equal %w[root_recording_id created_at id], Array(index.columns)
    assert_equal({ "created_at" => :desc, "id" => :desc }, index.orders)
    assert_nil index.where
    refute index.unique
    assert_nil index_named("index_rs_recordings_on_root_recording")

    assert type_page
    assert_equal %w[root_recording_id recordable_type created_at id], Array(type_page.columns)
    assert_nil type_page.where
  end

  def test_root_foreign_key_keeps_a_leading_index_and_the_composite_key_stays
    created_at_index = index_named("index_rs_recordings_on_root_created_at_id")
    identity = index_named("index_rs_recordings_on_id_and_root")
    parent_index = index_named("index_recording_studio_recordings_on_parent_recording_id")
    root_foreign_key = foreign_key_on(%w[root_recording_id])
    parent_root_foreign_key = foreign_key_named("fk_rs_recordings_on_parent_and_root")

    assert_equal "root_recording_id", Array(created_at_index.columns).first
    assert root_foreign_key
    assert identity.unique
    assert_equal %w[id root_recording_id], identity.columns.map(&:to_s)
    assert_equal %w[parent_recording_id], Array(parent_index.columns)
    assert_equal %w[parent_recording_id root_recording_id], Array(parent_root_foreign_key.column).map(&:to_s)
    assert_equal %w[id root_recording_id], Array(parent_root_foreign_key.primary_key).map(&:to_s)
  end

  private

  def index_named(name)
    RecordingStudio::Recording.connection.indexes(:recording_studio_recordings).find do |candidate|
      candidate.name == name
    end
  end

  def foreign_key_named(name)
    foreign_keys.find { |item| item.name == name }
  end

  def foreign_key_on(columns)
    foreign_keys.find { |item| Array(item.column).map(&:to_s) == columns }
  end

  def foreign_keys
    RecordingStudio::Recording.connection.foreign_keys(:recording_studio_recordings)
  end
end
