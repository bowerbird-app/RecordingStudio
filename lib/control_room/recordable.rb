# frozen_string_literal: true

module ControlRoom
  # Marks a recordable as immutable after persistence.
  module Recordable
    extend ActiveSupport::Concern

    included do
      before_update :raise_immutable_error
      before_destroy :raise_immutable_error
    end

    def readonly?
      persisted?
    end

    private

    def raise_immutable_error
      raise ActiveRecord::ReadOnlyRecord, "Recordables are immutable; use revise to create a new snapshot."
    end
  end
end
