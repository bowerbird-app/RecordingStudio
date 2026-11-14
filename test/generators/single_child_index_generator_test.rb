# frozen_string_literal: true

require "test_helper"
require "rails/generators"
require "rails/generators/test_case"
require "generators/recording_studio/single_child_index/single_child_index_generator"

class SingleChildIndexGeneratorTest < Rails::Generators::TestCase
  tests RecordingStudio::Generators::SingleChildIndexGenerator
  destination File.expand_path("../tmp/single_child_index_generator", __dir__)

  def setup
    prepare_destination
    @original_types = RecordingStudio.configuration.recordable_types.dup
    @original_declarations = RecordingStudio::RecordableDeclarations.declarations.dup
    @original_rules = RecordingStudio::SingleChildren.snapshot
  end

  def teardown
    RecordingStudio.configuration.recordable_types = @original_types
    RecordingStudio::RecordableDeclarations.replace_declarations!(@original_declarations)
    RecordingStudio::SingleChildren.restore!(@original_rules)
  end

  def test_writes_a_partial_unique_index_for_global_single_children
    run_generator
    migration = Dir.glob(File.join(destination_root, "db/migrate", "*_add_recording_studio_single_child_index.rb")).sole
    source = File.read(migration)

    assert_includes source, 'name: "index_recording_studio_recordings_on_single_child"'
    assert_includes source, "%i[parent_recording_id recordable_type]"
    assert_includes source, "unique: true"
    assert_includes source, 'where: "recordable_type IN (\'RecordingStudioCover\')"'
    refute_includes source, "kept_sql"
    refute_includes source, "trashed"
  end

  def test_writes_pairwise_limits_as_comments_and_skips_an_empty_index
    RecordingStudio.configuration.recordable_types = %w[Workspace RecordingStudioPage]
    RecordingStudio.declare_single_child(
      "RecordingStudioPage",
      under: "Workspace",
      key: "page-under-workspace"
    )

    run_generator
    source = File.read(generated_migration)

    assert_includes source, "RecordingStudioPage under Workspace"
    assert_includes source, "left out of this index"
    refute_includes source, "add_index"
    refute_includes source, "kept_sql"
  end

  private

  def generated_migration
    Dir.glob(File.join(destination_root, "db/migrate", "*_add_recording_studio_single_child_index.rb")).sole
  end
end
