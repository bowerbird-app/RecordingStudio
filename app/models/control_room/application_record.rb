# frozen_string_literal: true

module ControlRoom
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
