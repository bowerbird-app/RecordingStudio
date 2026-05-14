class ConfigController < ApplicationController
  def index
    @configuration_code = <<~RUBY
      RecordingStudio.configure do |config|
        # These are the recordable types currently registered with the engine.
        config.recordable_types = #{configuration.recordable_types.sort.inspect}

        # Resolve the actor from Current when callers do not pass one explicitly.
        config.actor = #{configured_proc_source(:actor, "-> { Current.actor }")}

        # Track the impersonator alongside the actor for audited changes.
        config.impersonator = #{configured_proc_source(:impersonator, "-> { Current.impersonator }")}

        # Broadcast ActiveSupport notifications when events are created.
        config.event_notifications_enabled = #{configuration.event_notifications_enabled.inspect}

        # Return the existing event when an idempotency key is reused.
        config.idempotency_mode = #{configuration.idempotency_mode.inspect}

        # Duplicate the current snapshot with Ruby's dup before persisting a revision.
        config.recordable_dup_strategy = #{configuration.recordable_dup_strategy.inspect}
      end
    RUBY
  end

  private

  def configuration
    RecordingStudio.configuration
  end

  def configured_proc_source(name, fallback)
    initializer_line_for(name) || fallback
  end

  def initializer_line_for(name)
    initializer_path = Rails.root.join("config/initializers/recording_studio.rb")
    line = File.readlines(initializer_path).find { |entry| entry.include?("config.#{name} =") }
    return if line.blank?

    line.split("=", 2).last.strip
  end
end
