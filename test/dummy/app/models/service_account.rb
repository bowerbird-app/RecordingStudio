class ServiceAccount < ApplicationRecord
  validates :name, presence: true
end
