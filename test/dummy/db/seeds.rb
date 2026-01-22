Workspace.find_or_create_by!(name: "Studio Workspace")

User.find_or_create_by!(name: "Avery Editor", email: "avery@example.com")
User.find_or_create_by!(name: "Quinn Writer", email: "quinn@example.com")

ServiceAccount.find_or_create_by!(name: "Automation Bot")

workspace = Workspace.first
actors = [
  User.find_by!(email: "avery@example.com"),
  User.find_by!(email: "quinn@example.com")
]

template_title = "Template: Shared Page"
template_page = Page.find_by(title: template_title)

if template_page.nil?
  page_recording = workspace.record(Page, actor: actors.first, metadata: { seeded: true, template: true }) do |page|
    page.title = template_title
    page.summary = "Template page used to test multiple actors sharing a recording target."
    page.version = 1
  end
  template_page = page_recording.recordable
else
  page_recording = nil
end

actors.each do |actor|
  existing_recording = RecordingStudio::Recording
    .for_container(workspace)
    .of_type(Page)
    .where(recordable_id: template_page.id)
    .joins(:events)
    .merge(RecordingStudio::Event.with_action("created").by_actor(actor))
    .first

  next if existing_recording

  new_recording = RecordingStudio.record!(
    action: "created",
    recordable: template_page,
    container: workspace,
    actor: actor,
    metadata: { seeded: true, template: true }
  ).recording
  page_recording ||= new_recording
end

page_recording ||= RecordingStudio::Recording
  .for_container(workspace)
  .of_type(Page)
  .where(recordable_id: template_page.id)
  .joins(:events)
  .merge(RecordingStudio::Event.with_action("created").by_actor(actors.first))
  .first

if workspace.recordings_of(Comment).where(parent_recording_id: page_recording.id).none?
  [
    "Looks great!",
    "Can we add more detail to the summary?",
    "Approved from my side."
  ].each do |body|
    workspace.record(Comment, actor: actors.first, parent_recording: page_recording, metadata: { seeded: true }) do |comment|
      comment.body = body
      comment.version = 1
    end
  end
end

# Backfill counter caches for recordables in the dummy app.
[Page, Comment].each do |recordable_class|
  recordable_class.update_all(recordings_count: 0, events_count: 0)

  RecordingStudio::Recording
    .where(recordable_type: recordable_class.name)
    .group(:recordable_id)
    .count
    .each do |recordable_id, count|
      recordable_class.where(id: recordable_id).update_all(recordings_count: count)
    end

  RecordingStudio::Event
    .where(recordable_type: recordable_class.name)
    .group(:recordable_id)
    .count
    .each do |recordable_id, count|
      recordable_class.where(id: recordable_id).update_all(events_count: count)
    end
end
