# frozen_string_literal: true

module RecordingStudio
  # Marker a gem includes on an error that explains a denial.
  #
  # Consumers must check `is_a?(RecordingStudio::Denial)` before reading `code`.
  # Do not duck-type `respond_to?(:code)`. `Stripe::StripeError` defines `#code`.
  #
  # Core stores the code and the details. It defines no codes and does not interpret them.
  module Denial
    # Shared checks for `GateDecision` and `Denial`.
    module Normalizer
      module_function

      def code(value)
        case value
        when nil then nil
        when Symbol then value
        when String then value.to_sym
        else
          raise ArgumentError, "code must be a Symbol, String, or nil"
        end
      end

      def details(value)
        return if value.nil?

        raise ArgumentError, "details must be a Hash or nil" unless value.is_a?(Hash)

        freeze_hash(value)
      end

      def freeze_hash(hash)
        frozen = {}
        hash.each do |key, item|
          name = symbol_key(key)
          raise ArgumentError, "details key #{name.inspect} is repeated after symbol conversion" if frozen.key?(name)

          frozen[name] = freeze_value(item)
        end
        frozen.freeze
      end

      def freeze_value(value)
        case value
        when String then -value
        when Float then finite_float(value)
        when Array then value.map { |item| freeze_value(item) }.freeze
        when Hash then freeze_hash(value)
        else freeze_scalar(value)
        end
      end

      def freeze_scalar(value)
        case value
        when nil, true, false, Symbol, Integer
          value
        else
          raise ArgumentError, "details values must be JSON-safe (got #{value.class})"
        end
      end

      def symbol_key(key)
        case key
        when Symbol then key
        when String then key.to_sym
        else
          raise ArgumentError, "details keys must be a Symbol or String"
        end
      end

      def finite_float(value)
        return value if value.finite?

        raise ArgumentError, "details values must be JSON-safe (got non-finite Float)"
      end

      private_class_method :freeze_hash, :freeze_value, :freeze_scalar, :symbol_key, :finite_float
    end

    EMPTY_DETAILS = {}.freeze

    def denial(code:, details: nil)
      @denial_code = Normalizer.code(code)
      @denial_details = Normalizer.details(details) || EMPTY_DETAILS
      self
    end

    def code
      @denial_code
    end

    def details
      @denial_details || EMPTY_DETAILS
    end
  end
end
