# frozen_string_literal: true

module RecordingStudio
  module Capabilities
    module Duplicable
      extend ActiveSupport::Concern

      included do |base|
        RecordingStudio.enable_capability(:duplicable, on: base.name)
      end
    end
  end
end
