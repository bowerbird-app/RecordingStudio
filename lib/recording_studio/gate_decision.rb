# frozen_string_literal: true

require_relative "denial"

module RecordingStudio
  # Immutable allow or deny result from RecordingStudio.check_gate.
  # Core stores the decision and does not redirect.
  # `code` and `details` are opaque. Core does not interpret them.
  class GateDecision
    def self.allow
      new(
        allowed: true,
        redirect_to: nil,
        reason: nil,
        gate: nil,
        check: nil,
        code: nil,
        details: nil
      )
    end

    # The public deny shape is these six keywords. Existing gates omit code and details.
    # rubocop:disable Metrics/ParameterLists
    def self.deny(redirect_to: nil, reason: nil, gate: nil, check: nil, code: nil, details: nil)
      new(
        allowed: false,
        redirect_to: redirect_to,
        reason: reason,
        gate: gate,
        check: check,
        code: code,
        details: details
      )
    end

    attr_reader :redirect_to, :reason, :gate, :check, :code, :details

    def initialize(allowed:, redirect_to:, reason:, gate:, check:, code: nil, details: nil)
      @allowed = allowed
      @redirect_to = freeze_text(redirect_to)
      @reason = freeze_text(reason)
      @gate = gate
      @check = check
      @code = Denial::Normalizer.code(code)
      @details = Denial::Normalizer.details(details)
      freeze
    end
    # rubocop:enable Metrics/ParameterLists

    def allowed?
      @allowed
    end

    def denied?
      !@allowed
    end

    def ==(other)
      other.instance_of?(self.class) && fields == other.fields
    end
    alias eql? ==

    def hash
      fields.hash
    end

    protected

    def fields
      [self.class, @allowed, redirect_to, reason, gate, check, code, details]
    end

    private

    def freeze_text(value)
      value.is_a?(String) ? -value : value
    end
  end
end
