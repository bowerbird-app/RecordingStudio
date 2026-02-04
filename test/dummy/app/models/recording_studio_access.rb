class RecordingStudioAccess < RecordingStudio::ApplicationRecord
  belongs_to :grantee, polymorphic: true

  enum access_level: { view: "view", edit: "edit" }, _default: "view"
end
