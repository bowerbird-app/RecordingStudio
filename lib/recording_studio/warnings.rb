# frozen_string_literal: true

module RecordingStudio
  module Warnings
    module_function

    def warn(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        Kernel.warn(message)
      end
    end

    def deprecation(message, horizon: "2.0")
      if defined?(ActiveSupport::Deprecation)
        ActiveSupport::Deprecation.new(horizon, "RecordingStudio").warn(message)
      else
        warn(message)
      end
    end
  end
end
