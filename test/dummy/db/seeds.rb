Workspace.find_or_create_by!(name: "Studio Workspace")

User.find_or_create_by!(name: "Avery Editor", email: "avery@example.com")
User.find_or_create_by!(name: "Quinn Writer", email: "quinn@example.com")

ServiceAccount.find_or_create_by!(name: "Automation Bot")

workspace = Workspace.first
actor = User.first

page_recording = workspace.recordings_of(Page).first

if page_recording.nil?
  page_recording = workspace.record(Page, actor: actor, metadata: { seeded: true }) do |page|
    page.title = "Welcome to ControlRoom"
    page.summary = "This page lives in a recording with immutable snapshots."
    page.version = 1
  end
end

if workspace.recordings_of(Comment).where(parent_recording_id: page_recording.id).none?
  [
    "Looks great!",
    "Can we add more detail to the summary?",
    "Approved from my side."
  ].each do |body|
    workspace.record(Comment, actor: actor, parent_recording: page_recording, metadata: { seeded: true }) do |comment|
      comment.body = body
      comment.version = 1
    end
  end
end
