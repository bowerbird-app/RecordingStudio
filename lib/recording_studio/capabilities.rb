# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    class << self
      def include_for(name, **options, &block)
        capability_name = name
        captured_options = options.dup

        Module.new do
          extend ActiveSupport::Concern

          included do |base|
            RecordingStudio.enable_capability(capability_name, on: base)
            RecordingStudio.set_capability_options(capability_name, on: base, **captured_options)
            block&.call(base)
          end
        end
      end
    end
  end
end
