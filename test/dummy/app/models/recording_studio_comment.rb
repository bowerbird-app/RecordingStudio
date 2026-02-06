class RecordingStudioComment < ApplicationRecord
  validates :body, presence: true
end
