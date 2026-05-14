class MethodsController < ApplicationController
  METHOD_CATALOG = [
    {
      title: "Configure Recording Studio",
      subtitle: "RecordingStudio.configure",
      code: <<~'RUBY'
        RecordingStudio.configure do |config|
          # Register the recordables your app exposes to the engine.
          config.recordable_types = ["Workspace", "Page", "Folder"]
          config.recordable_dup_strategy = :dup
        end
      RUBY
    },
    {
      title: "Register a Recordable Type",
      subtitle: "RecordingStudio.register_recordable_type",
      code: <<~'RUBY'
        # Call this during boot or from addon setup.
        RecordingStudio.register_recordable_type("Page")
        RecordingStudio.register_recordable_type("Workspace")
      RUBY
    },
    {
      title: "Register Capability Methods",
      subtitle: "RecordingStudio.register_capability",
      code: <<~'RUBY'
        module Capabilities
          module Commentable
            module RecordingMethods
              def comments
                child_recordings.of_type("Comment")
              end
            end
          end
        end

        # This mixes the API into RecordingStudio::Recording.
        RecordingStudio.register_capability(:commentable, Capabilities::Commentable::RecordingMethods)
      RUBY
    },
    {
      title: "Apply Registered Capabilities",
      subtitle: "RecordingStudio.apply_capabilities!",
      code: <<~'RUBY'
        Rails.application.config.to_prepare do
          # Useful when addon constants are reloaded in development.
          RecordingStudio.apply_capabilities!
        end
      RUBY
    },
    {
      title: "Enable a Capability for a Recordable",
      subtitle: "RecordingStudio.enable_capability",
      code: <<~'RUBY'
        class Page < ApplicationRecord
          include Module.new {
            def self.included(base)
              RecordingStudio.enable_capability(:commentable, on: base.name)
            end
          }
        end
      RUBY
    },
    {
      title: "Set Capability Options",
      subtitle: "RecordingStudio.set_capability_options",
      code: <<~'RUBY'
        RecordingStudio.set_capability_options(
          :commentable,
          on: "Page",
          comment_class: "Comment"
        )
      RUBY
    },
    {
      title: "Read Capability Options",
      subtitle: "RecordingStudio.capability_options",
      code: <<~'RUBY'
        options = RecordingStudio.capability_options(:commentable, for_type: "Page")

        # => { comment_class: "Comment" }
        options.fetch(:comment_class)
      RUBY
    },
    {
      title: "Normalize a Recordable Type Name",
      subtitle: "RecordingStudio.recordable_type_name",
      code: <<~'RUBY'
        page = Page.new(title: "Quarterly Plan")

        RecordingStudio.recordable_type_name(page)
        # => "Page"
      RUBY
    },
    {
      title: "Resolve a Recordable Class",
      subtitle: "RecordingStudio.resolve_recordable_type",
      code: <<~'RUBY'
        recordable_class = RecordingStudio.resolve_recordable_type("Page")

        # => Page
        recordable_class.new(title: "Resolved from the registry")
      RUBY
    },
    {
      title: "Build a Stable Recordable Identifier",
      subtitle: "RecordingStudio.recordable_identifier",
      code: <<~'RUBY'
        page = Page.find(42)

        # Handy when you need a stable identifier for logs or payloads.
        RecordingStudio.recordable_identifier(page)
      RUBY
    },
    {
      title: "Build a Global ID",
      subtitle: "RecordingStudio.recordable_global_id",
      code: <<~'RUBY'
        workspace = Workspace.first

        # Uses Rails GlobalID so jobs can re-load the record later.
        RecordingStudio.recordable_global_id(workspace)
      RUBY
    },
    {
      title: "Look Up the Duplication Strategy",
      subtitle: "RecordingStudio.dup_strategy_for",
      code: <<~'RUBY'
        strategy = RecordingStudio.dup_strategy_for("Page")

        # The returned value may be :dup or a callable.
        strategy
      RUBY
    },
    {
      title: "Duplicate a Recordable Snapshot",
      subtitle: "RecordingStudio.duplicate_recordable",
      code: <<~'RUBY'
        page = Page.find(7)
        cloned_page = RecordingStudio.duplicate_recordable(page)

        # Revise workflows usually save this new snapshot next.
        cloned_page.save!
      RUBY
    },
    {
      title: "Append an Event Directly",
      subtitle: "RecordingStudio.record!",
      code: <<~'RUBY'
        event = RecordingStudio.record!(
          action: "created",
          recordable: Workspace.create!(name: "Docs"),
          root_recording: RecordingStudio::Recording.create!(recordable: Workspace.create!(name: "Root")),
          metadata: { source: "seed" }
        )

        # Returns the event that was created or de-duplicated.
        event
      RUBY
    },
    {
      title: "Create a Child Recording",
      subtitle: "root_recording.record",
      code: <<~'RUBY'
        page_recording = root_recording.record(Page, actor: current_user) do |page|
          # Mutate the fresh snapshot before RecordingStudio persists it.
          page.title = "Shipping Plan"
          page.body = "Everything starts from the root recording."
        end
      RUBY
    },
    {
      title: "Revise an Existing Recording",
      subtitle: "root_recording.revise",
      code: <<~'RUBY'
        root_recording.revise(page_recording, actor: current_user, metadata: { reason: "review" }) do |page|
          # You get a duplicated snapshot here, not the original recordable.
          page.title = "Shipping Plan v2"
        end
      RUBY
    },
    {
      title: "Log an Event Through the Root",
      subtitle: "root_recording.log_event",
      code: <<~'RUBY'
        root_recording.log_event(
          page_recording,
          action: "reviewed",
          actor: current_user,
          metadata: { status: "approved" }
        )
      RUBY
    },
    {
      title: "Log an Event on a Recording",
      subtitle: "recording.log_event!",
      code: <<~'RUBY'
        page_recording.log_event!(
          action: "published",
          actor: current_user,
          idempotency_key: "publish-page-#{page_recording.id}"
        )
      RUBY
    },
    {
      title: "Revert to an Older Snapshot",
      subtitle: "root_recording.revert",
      code: <<~'RUBY'
        previous_snapshot = page_recording.events.second.previous_recordable

        root_recording.revert(
          page_recording,
          to_recordable: previous_snapshot,
          actor: current_user,
          metadata: { reason: "rollback" }
        )
      RUBY
    },
    {
      title: "Query Descendant Recordings",
      subtitle: "root_recording.recordings_query",
      code: <<~'RUBY'
        root_recording.recordings_query(
          type: "Page",
          recordable_filters: { title: "Quarterly Plan" },
          recordable_order: "title asc",
          include_children: true
        )
      RUBY
    },
    {
      title: "Filter Recordings by Class",
      subtitle: "root_recording.recordings_of",
      code: <<~'RUBY'
        # Returns recordings whose current recordable is a Page.
        page_recordings = root_recording.recordings_of(Page)
      RUBY
    },
    {
      title: "Read Filtered Events",
      subtitle: "recording.events",
      code: <<~'RUBY'
        page_recording.events(
          actions: %w[created updated reviewed],
          actor: current_user,
          limit: 20
        )
      RUBY
    },
    {
      title: "Add a Comment Through a Capability",
      subtitle: "recording.comment!",
      code: <<~'RUBY'
        page_recording.comment!(
          body: "This section is ready for editorial review.",
          actor: current_user,
          metadata: { channel: "inline-review" }
        )
      RUBY
    },
    {
      title: "List Comment Recordings",
      subtitle: "recording.comments",
      code: <<~'RUBY'
        # Capability methods run on RecordingStudio::Recording.
        comments = page_recording.comments
      RUBY
    }
  ].freeze

  def index
    @method_catalog = METHOD_CATALOG
  end
end
