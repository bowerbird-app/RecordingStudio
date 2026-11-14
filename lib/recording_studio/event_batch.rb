# frozen_string_literal: true

require "recording_studio/event_batch/entries"
require "recording_studio/event_batch/commit"

module RecordingStudio
  # Appends events to existing recordings in one INSERT.
  class EventBatch
    def self.record!(entries)
      new(entries).record!
    end

    def initialize(entries)
      @entries = entries
    end

    def record!
      RecordingStudio::DelegatedTypeRegistrar.apply!
      prepared = Entries.prepare(@entries)
      return [] if prepared.empty?

      RecordingStudio::Recording.transaction { Commit.call(prepared) }
    end
  end
end
