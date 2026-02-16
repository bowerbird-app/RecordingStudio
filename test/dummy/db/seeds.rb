workspace = Workspace.find_or_create_by!(name: "Studio Workspace")
quinn_workspace = Workspace.find_or_create_by!(name: "Quinn Workspace")

default_password = "password123"

admin_user = User.find_or_initialize_by(email: "admin@example.com")
admin_user.name = "Admin User"
admin_user.password = default_password
admin_user.password_confirmation = default_password
admin_user.admin = true
admin_user.save!

avery = User.find_or_initialize_by(email: "avery@example.com")
avery.name = "Avery Editor"
avery.password = default_password
avery.password_confirmation = default_password
avery.save!

quinn = User.find_or_initialize_by(email: "quinn@example.com")
quinn.name = "Quinn Writer"
quinn.password = default_password
quinn.password_confirmation = default_password
quinn.save!

[ "Background task", "AI agent" ].each do |name|
  SystemActor.find_or_create_by!(name: name)
end

studio_root = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: workspace, parent_recording_id: nil)
quinn_root = RecordingStudio::Recording.unscoped.find_or_create_by!(recordable: quinn_workspace, parent_recording_id: nil)
actors = [
  User.find_by!(email: "avery@example.com"),
  User.find_by!(email: "quinn@example.com")
]

def seed_root_access!(root_recording, actor:, role:)
  role_value = RecordingStudio::Access.roles.fetch(role.to_s)

  existing = RecordingStudio::Recording.unscoped
    .where(root_recording_id: root_recording.id, parent_recording_id: root_recording.id, recordable_type: "RecordingStudio::Access")
    .joins("INNER JOIN recording_studio_accesses ON recording_studio_accesses.id = recording_studio_recordings.recordable_id")
    .where(recording_studio_accesses: { actor_type: actor.class.name, actor_id: actor.id, role: role_value })
    .exists?

  return if existing

  access = RecordingStudio::Access.create!(actor: actor, role: role)
  RecordingStudio::Recording.create!(
    root_recording: root_recording,
    parent_recording: root_recording,
    recordable: access
  )
end

seed_root_access!(studio_root, actor: admin_user, role: :admin)
seed_root_access!(studio_root, actor: avery, role: :view)
seed_root_access!(quinn_root, actor: quinn, role: :admin)

template_title = "Template: Shared Page"
template_page = RecordingStudioPage.find_by(title: template_title)

if template_page.nil?
  page_recording = studio_root.record(RecordingStudioPage, actor: actors.first, metadata: { seeded: true, template: true }) do |page|
    page.title = template_title
    page.summary = "Template page used to test multiple actors sharing a recording target."
  end
  template_page = page_recording.recordable
else
  page_recording = nil
end

actors.each do |actor|
  existing_recording = RecordingStudio::Recording
    .for_root(studio_root.id)
    .of_type(RecordingStudioPage)
    .where(recordable_id: template_page.id)
    .joins(:events)
    .merge(RecordingStudio::Event.with_action("created").by_actor(actor))
    .first

  next if existing_recording

  new_recording = RecordingStudio.record!(
    action: "created",
    recordable: template_page,
    root_recording: studio_root,
    parent_recording: studio_root,
    actor: actor,
    metadata: { seeded: true, template: true }
  ).recording
  page_recording ||= new_recording
end

page_recording ||= RecordingStudio::Recording
  .for_root(studio_root.id)
  .of_type(RecordingStudioPage)
  .where(recordable_id: template_page.id)
  .joins(:events)
  .merge(RecordingStudio::Event.with_action("created").by_actor(actors.first))
  .first

if studio_root.recordings_of(RecordingStudioComment).where(parent_recording_id: page_recording.id).none?
  [
    "Looks great!",
    "Can we add more detail to the summary?",
    "Approved from my side."
  ].each do |body|
    studio_root.record(RecordingStudioComment, actor: actors.first, parent_recording: page_recording, metadata: { seeded: true }) do |comment|
      comment.body = body
    end
  end
end

unless RecordingStudioFolder.exists?(name: "Projects")
  projects_recording = studio_root.record(RecordingStudioFolder, actor: admin_user, metadata: { seeded: true }) do |folder|
    folder.name = "Projects"
  end

  public_recording = studio_root.record(RecordingStudioFolder, actor: admin_user, parent_recording: projects_recording, metadata: { seeded: true }) do |folder|
    folder.name = "Public"
  end

  studio_root.record(RecordingStudioPage, actor: admin_user, parent_recording: public_recording, metadata: { seeded: true }) do |page|
    page.title = "Public Roadmap"
  end

  confidential_recording = studio_root.record(RecordingStudioFolder, actor: admin_user, parent_recording: projects_recording, metadata: { seeded: true }) do |folder|
    folder.name = "Confidential"
  end

  boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
  RecordingStudio::Recording.create!(root_recording: studio_root, recordable: boundary, parent_recording: confidential_recording)

  internal_recording = studio_root.record(RecordingStudioFolder, actor: admin_user, parent_recording: confidential_recording, metadata: { seeded: true }) do |folder|
    folder.name = "Internal"
  end

  studio_root.record(RecordingStudioPage, actor: admin_user, parent_recording: internal_recording, metadata: { seeded: true }) do |page|
    page.title = "Strategy"
  end

  budget_recording = studio_root.record(RecordingStudioPage, actor: admin_user, parent_recording: confidential_recording, metadata: { seeded: true }) do |page|
    page.title = "Budget"
  end

  access = RecordingStudio::Access.create!(actor: quinn, role: :edit)
  RecordingStudio::Recording.create!(root_recording: studio_root, recordable: access, parent_recording: budget_recording)
end

# Backfill counter caches for recordables in the dummy app.
[ RecordingStudioPage, RecordingStudioComment, RecordingStudioFolder ].each do |recordable_class|
  recordable_class.update_all(recordings_count: 0, events_count: 0)

  RecordingStudio::Recording
    .where(recordable_type: recordable_class.name)
    .reorder(nil)
    .group(:recordable_id)
    .count
    .each do |recordable_id, count|
      recordable_class.where(id: recordable_id).update_all(recordings_count: count)
    end

  RecordingStudio::Event
    .where(recordable_type: recordable_class.name)
    .reorder(nil)
    .group(:recordable_id)
    .count
    .each do |recordable_id, count|
      recordable_class.where(id: recordable_id).update_all(events_count: count)
    end
end
