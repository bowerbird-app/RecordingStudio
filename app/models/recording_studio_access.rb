# frozen_string_literal: true

class RecordingStudioAccess < RecordingStudio::ApplicationRecord
  belongs_to :grantee, polymorphic: true

  enum access_level: { view: "view", edit: "edit" }, _default: "view"
end

RecordingStudio.register_recordable_type("RecordingStudioAccess")
