# frozen_string_literal: true

# Cross-root subtree move of 100_000 descendant rows.
# Not part of the test suite. Run from the repo root:
#
#   bundle exec ruby script/benchmark_subtree_move.rb
#
# Uses the test database Recording Studio tests use, then deletes the rows it inserted.

require "securerandom"

ENV["SECRET_KEY_BASE"] ||= SecureRandom.hex(64)
ENV["RAILS_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["DB_USER"] ||= "postgres"
ENV["DB_PASSWORD"] ||= "postgres"
ENV["DB_HOST"] ||= "localhost"
ENV["DB_PORT"] ||= "5432"
ENV["DB_NAME_TEST"] ||= ENV.fetch("DB_NAME", "gem_template_test")
db_user = ENV.fetch("DB_USER", nil)
db_password = ENV.fetch("DB_PASSWORD", nil)
db_host = ENV.fetch("DB_HOST", nil)
db_port = ENV.fetch("DB_PORT", nil)
db_name_test = ENV.fetch("DB_NAME_TEST", nil)
ENV["PGUSER"] ||= db_user
ENV["PGPASSWORD"] ||= db_password
ENV["DATABASE_URL"] ||= "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name_test}"

require_relative "../test/dummy/config/environment"

COUNT = 100_000
BATCH = 5_000

def clock
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def milliseconds(seconds)
  (seconds * 1000).round(1)
end

actor = nil
source = nil
destination = nil
source_workspace = nil
destination_workspace = nil
parent_page = nil

begin
  actor = User.create!(
    name: "Benchmark",
    email: "benchmark-#{SecureRandom.hex(4)}@example.com",
    password: "password123",
    password_confirmation: "password123"
  )
  source_workspace = Workspace.create!(name: "Benchmark source #{SecureRandom.hex(4)}")
  destination_workspace = Workspace.create!(name: "Benchmark destination #{SecureRandom.hex(4)}")
  source = RecordingStudio.create_root_recording!(source_workspace, actor: actor)
  destination = RecordingStudio.create_root_recording!(destination_workspace, actor: actor)
  parent = source.record(RecordingStudioPage, actor: actor) { |page| page.title = "Moved parent" }
  parent_page = parent.recordable
  now = Time.current
  inserted = 0
  insert_started = clock

  while inserted < COUNT
    size = [BATCH, COUNT - inserted].min
    rows = Array.new(size) do
      {
        id: SecureRandom.uuid,
        recordable_type: "RecordingStudioPage",
        recordable_id: SecureRandom.uuid,
        parent_recording_id: parent.id,
        root_recording_id: source.id,
        created_at: now,
        updated_at: now
      }
    end
    RecordingStudio::Recording.insert_all(rows)
    inserted += size
  end
  insert_seconds = clock - insert_started

  descendant_count = RecordingStudio::Recording.where(parent_recording_id: parent.id).count
  raise "expected #{COUNT} descendants, found #{descendant_count}" unless descendant_count == COUNT

  timings = {}
  transaction_started = clock
  RecordingStudio::Recording.transaction do
    started = clock
    locks = RecordingStudio.lock_for_move!(parent, to_parent: destination, to_root: destination)
    timings[:lock_for_move] = clock - started
    raise "descendant count #{locks[:descendant_ids].size}" unless locks[:descendant_ids].size == COUNT

    started = clock
    RecordingStudio::Recording.where(id: locks[:descendant_ids]).update_all(root_recording_id: destination.id)
    timings[:update_all] = clock - started

    started = clock
    locks[:recording].update!(parent_recording: locks[:to_parent], root_recording_id: destination.id)
    timings[:save] = clock - started
    timings[:before_commit] = clock - transaction_started
  end
  timings[:total] = clock - transaction_started
  timings[:commit] = timings[:total] - timings[:before_commit]

  moved = RecordingStudio::Recording.where(root_recording_id: destination.id).where.not(id: destination.id).count
  raise "expected #{COUNT + 1} moved rows, found #{moved}" unless moved == COUNT + 1

  puts "database=#{RecordingStudio::Recording.connection.current_database} descendants=#{COUNT}"
  puts "insert_all_seconds=#{insert_seconds.round(3)}"
  %i[lock_for_move update_all save commit total].each do |name|
    puts "#{name}_ms=#{milliseconds(timings.fetch(name))}"
  end
ensure
  if defined?(RecordingStudio::Recording) && RecordingStudio::Recording.connection.active?
    root_ids = [source&.id, destination&.id].compact
    if root_ids.any?
      RecordingStudio::Recording.connection.disable_referential_integrity do
        RecordingStudio::Event.where(root_recording_id: root_ids).delete_all
        RecordingStudio::Recording.where(root_recording_id: root_ids).delete_all
      end
    end
    parent_page&.delete
    source_workspace&.delete
    destination_workspace&.delete
    User.where(email: actor.email).delete_all if actor
  end
end
