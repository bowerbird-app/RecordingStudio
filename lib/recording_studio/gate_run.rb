# frozen_string_literal: true

module RecordingStudio
  class GateRun
    class << self
      def listings(gate)
        items_for(gate).map { |item| item[:listing] }
      end

      def call(gate, actor:, recording: nil, **context)
        items_for(gate).each do |item|
          next unless item[:enabled]

          decision = new(item, actor, recording, context).result
          return decision if decision&.denied?
        end
        GateDecision.allow
      end

      private

      def items_for(gate)
        items, unknown = GateRegistry.snapshot(gate)
        unknown.each { |check_name| warn_unknown(gate, check_name) }
        items
      end

      def warn_unknown(gate, check)
        message = "[RecordingStudio::Gates] Ignoring override for unknown check " \
                  "#{check.inspect} on gate #{gate.inspect}"
        logger = rails_logger
        return logger.debug(message) if logger.respond_to?(:debug)

        RecordingStudio::Warnings.warn(message)
      end

      def rails_logger
        return unless defined?(Rails) && Rails.respond_to?(:logger)

        Rails.logger
      end
    end

    def initialize(item, actor, recording, context)
      @item = item
      @actor = actor
      @recording = recording
      @context = context
    end

    def result
      decision_for(@item[:callable].call(actor: @actor, recording: @recording, **@context))
    rescue StandardError => e
      warn_failure("#{e.class}: #{e.message}")
      deny
    end

    private

    def decision_for(value)
      return if value == true
      return deny if value == false
      return deny_from(value) if value.is_a?(GateDecision)

      warn_failure("expected true, false, or RecordingStudio::GateDecision, got #{value.class}")
      deny
    end

    def deny_from(value)
      return if value.allowed?

      deny(redirect_to: value.redirect_to, reason: value.reason)
    end

    def deny(redirect_to: nil, reason: nil)
      GateDecision.deny(redirect_to: redirect_to, reason: reason, gate: @item[:gate], check: @item[:name])
    end

    def warn_failure(detail)
      RecordingStudio::Warnings.warn(
        "[RecordingStudio::Gates] Check #{@item[:name].inspect} on gate #{@item[:gate].inspect} " \
        "failed closed: #{detail}"
      )
    end
  end
end
