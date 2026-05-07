# frozen_string_literal: true

module RecordingStudio
  module Duplication
    COUNTER_CACHE_ATTRIBUTES = %i[recordings_count events_count].freeze

    module_function

    def duplicate_recordable(recordable)
      return if recordable.nil?

      strategy = RecordingStudio.dup_strategy_for(recordable)
      return strategy.call(recordable) if strategy.respond_to?(:call)

      reset_counter_caches(recordable.dup)
    end

    def reset_counter_caches(recordable)
      return if recordable.nil?

      COUNTER_CACHE_ATTRIBUTES.each do |attribute|
        setter = "#{attribute}="
        recordable.public_send(setter, 0) if recordable.respond_to?(setter)
      end

      recordable
    end
  end
end
