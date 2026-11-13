# frozen_string_literal: true

module RecordingStudio
  # Immutable allow or deny result from RecordingStudio.check_gate.
  # Core stores the decision and does not redirect.
  class GateDecision
    def self.allow
      new(allowed: true, redirect_to: nil, reason: nil, gate: nil, check: nil)
    end

    def self.deny(redirect_to: nil, reason: nil, gate: nil, check: nil)
      new(
        allowed: false,
        redirect_to: redirect_to,
        reason: reason,
        gate: gate,
        check: check
      )
    end

    attr_reader :redirect_to, :reason, :gate, :check

    def initialize(allowed:, redirect_to:, reason:, gate:, check:)
      @allowed = allowed
      @redirect_to = freeze_text(redirect_to)
      @reason = freeze_text(reason)
      @gate = gate
      @check = check
      freeze
    end

    def allowed?
      @allowed
    end

    def denied?
      !@allowed
    end

    def ==(other)
      other.instance_of?(self.class) &&
        allowed? == other.allowed? &&
        redirect_to == other.redirect_to &&
        reason == other.reason &&
        gate == other.gate &&
        check == other.check
    end
    alias eql? ==

    def hash
      [self.class, @allowed, redirect_to, reason, gate, check].hash
    end

    private

    def freeze_text(value)
      value.is_a?(String) ? -value : value
    end
  end
end
