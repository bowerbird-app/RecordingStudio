Workspace.find_or_create_by!(name: "Studio Workspace")

User.find_or_create_by!(name: "Avery Editor", email: "avery@example.com")
User.find_or_create_by!(name: "Quinn Writer", email: "quinn@example.com")

ServiceAccount.find_or_create_by!(name: "Automation Bot")

workspace = Workspace.first
actor = User.first

if workspace.recordings_of(Page).kept.none?
  workspace.record(Page, actor: actor, metadata: { seeded: true }) do |page|
    page.title = "Welcome to ControlRoom"
    page.summary = "This page lives in a recording with immutable snapshots."
    page.version = 1
  end
end
