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
        page = Page.find("9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef")

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
      title: "Read a Canonical Display Name",
      subtitle: "RecordingStudio.recordable_name",
      code: <<~'RUBY'
        page = Page.new(title: "Report blue")

        # Uses recordable_name first, then engine fallbacks.
        RecordingStudio.recordable_name(page)
        # => "Report blue"
      RUBY
    },
    {
      title: "Read a Human Type Label",
      subtitle: "RecordingStudio.recordable_type_label",
      code: <<~'RUBY'
        page = Page.new(title: "Report blue")

        RecordingStudio.recordable_type_label(page)
        # => "Page"
      RUBY
    },
    {
      title: "Read a Recording Display Name",
      subtitle: "recording.name",
      code: <<~'RUBY'
        page_recording.name
        # => "Report blue"
      RUBY
    },
    {
      title: "Read a Recording Type Label",
      subtitle: "recording.type_label",
      code: <<~'RUBY'
        page_recording.type_label
        # => "Page"
      RUBY
    },
    {
      title: "Read a Recording Display Title",
      subtitle: "recording.title",
      code: <<~'RUBY'
        page_recording.title
        # => "Report blue"
      RUBY
    },
    {
      title: "Read a Recording Summary",
      subtitle: "recording.summary",
      code: <<~'RUBY'
        comment_recording.summary
        # => "A concise update for the activity feed."
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
        page = Page.find("c14b6f72-4c7f-4b6d-9d96-8f8d3e2c1b91")
        cloned_page = RecordingStudio.duplicate_recordable(page)

        # Revise workflows usually save this new snapshot next.
        cloned_page.save!
      RUBY
    },
    {
      title: "Create or Find a Root Recording",
      subtitle: "RecordingStudio.root_recording_for",
      code: <<~'RUBY'
        workspace = Workspace.find("9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef")

        root_recording = RecordingStudio.root_recording_for(workspace)
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
      title: "Find One Recording by Recordable",
      subtitle: "root_recording.recording_for",
      code: <<~'RUBY'
        page = Page.find(params[:id])

        root_recording.recording_for(page)
      RUBY
    },
    {
      title: "Find Multiple Recordings by Recordable",
      subtitle: "root_recording.recordings_for",
      code: <<~'RUBY'
        pages = Page.where(topic: "Quarterly Plan")

        root_recording.recordings_for(pages)
      RUBY
    },
    {
      title: "Read Raw Recordables for a Type",
      subtitle: "root_recording.recordables_of",
      code: <<~'RUBY'
        root_recording.recordables_of(
          Page,
          include_children: true,
          recordable_filters: { title: "Quarterly Plan" }
        )
      RUBY
    },
    {
      title: "Read Direct Children for a Parent",
      subtitle: "root_recording.child_recordings_of",
      code: <<~'RUBY'
        root_recording.child_recordings_of(
          folder_recording,
          type: Page,
          order: { updated_at: :asc }
        )
      RUBY
    },
    {
      title: "Query a Root Event Timeline",
      subtitle: "root_recording.events_query",
      code: <<~'RUBY'
        root_recording.events_query(
          actions: %w[published reviewed],
          type: Page,
          include_children: true,
          limit: 20
        )
      RUBY
    },
    {
      title: "Find Recordings Touched by Matching Events",
      subtitle: "root_recording.recordings_with_events",
      code: <<~'RUBY'
        root_recording.recordings_with_events(
          actions: "published",
          actor: current_user,
          include_children: true
        )
      RUBY
    },
    {
      title: "List All Recording Wrappers",
      subtitle: "RecordingStudio::Recording.all",
      code: <<~'RUBY'
        RecordingStudio::Recording.all
      RUBY
    },
    {
      title: "Filter Recording Wrappers by Root",
      subtitle: "RecordingStudio::Recording.for_root",
      code: <<~'RUBY'
        RecordingStudio::Recording.for_root(root_recording.id)
      RUBY
    },
    {
      title: "Filter Recording Wrappers by Type",
      subtitle: "RecordingStudio::Recording.of_type",
      code: <<~'RUBY'
        RecordingStudio::Recording.of_type(Page)
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
      title: "Read the Latest Event",
      subtitle: "recording.latest_event",
      code: <<~'RUBY'
        page_recording.latest_event
        # => most recent event by occurred_at / created_at
      RUBY
    },
    {
      title: "Read the First Event",
      subtitle: "recording.first_event",
      code: <<~'RUBY'
        page_recording.first_event
        # => oldest event in the timeline
      RUBY
    },
    {
      title: "Find an Event by Idempotency Key",
      subtitle: "recording.event_by_idempotency_key",
      code: <<~'RUBY'
        page_recording.event_by_idempotency_key("publish-page-#{page_recording.id}")
      RUBY
    },
    {
      title: "Read Subtree Events",
      subtitle: "recording.subtree_events",
      code: <<~'RUBY'
        # Returns one merged timeline ordered newest-first by event time.
        # limit applies after combining self + descendant events.
        page_recording.subtree_events(
          descendant_scope: ->(recordings) { recordings.where(recordable_type: "Page") },
          actions: %w[created published],
          limit: 20
        )
      RUBY
    },
    {
      title: "Query Events for a Root Recording",
      subtitle: "RecordingStudio::Event.for_root",
      code: <<~'RUBY'
        RecordingStudio::Event.for_root(root_recording).recent.limit(20)
      RUBY
    },
    {
      title: "Query Events for One Recording",
      subtitle: "RecordingStudio::Event.for_recording",
      code: <<~'RUBY'
        RecordingStudio::Event.for_recording(page_recording).recent.limit(20)
      RUBY
    },
    {
      title: "Filter Events by Actor",
      subtitle: "RecordingStudio::Event.by_actor",
      code: <<~'RUBY'
        RecordingStudio::Event.by_actor(current_user)
      RUBY
    },
    {
      title: "Filter Events by Action",
      subtitle: "RecordingStudio::Event.with_action",
      code: <<~'RUBY'
        RecordingStudio::Event.with_action(%w[published reviewed])
      RUBY
    },
    {
      title: "Order Events Newest First",
      subtitle: "RecordingStudio::Event.recent",
      code: <<~'RUBY'
        RecordingStudio::Event.recent.limit(20)
      RUBY
    },
    {
      title: "Filter Events by Impersonator",
      subtitle: "RecordingStudio::Event.by_impersonator",
      code: <<~'RUBY'
        RecordingStudio::Event.by_impersonator(current_admin)
      RUBY
    },
    {
      title: "Filter Events by Time Range",
      subtitle: "RecordingStudio::Event.between",
      code: <<~'RUBY'
        RecordingStudio::Event.between(2.days.ago, Time.current)
      RUBY
    }
  ].freeze

  METHOD_RESPONSE_DETAILS = {
    "RecordingStudio.configure" => {
      returns_kind: "Side effect",
      returns: "Block return value; use this API to mutate RecordingStudio::Configuration rather than read data.",
      yields: "RecordingStudio::Configuration",
      notes: "Treat this as setup code, not a runtime query API.",
      example_response: <<~'TEXT'
        config.recordable_types
        # => ["Workspace", "Page", "Folder"]

        config.recordable_dup_strategy
        # => :dup
      TEXT
    },
    "RecordingStudio.register_recordable_type" => {
      returns_kind: "Side effect",
      returns: "No stable return contract; registers the type and reapplies delegated-type wiring.",
      notes: "Use during boot or addon setup, not for fetching data at runtime.",
      example_response: <<~'TEXT'
        RecordingStudio.configuration.recordable_types
        # => ["Page", "Workspace"]
      TEXT
    },
    "RecordingStudio.recordable_type_name" => {
      returns_kind: "String",
      returns: "String or nil",
      notes: "Returns the normalized recordable type name for an instance, class, or type string.",
      example_response: <<~'TEXT'
        "Page"
      TEXT
    },
    "RecordingStudio.resolve_recordable_type" => {
      returns_kind: "Class",
      returns: "Class or nil",
      notes: "Returns the resolved recordable class constant when the type is known.",
      example_response: <<~'TEXT'
        Page
      TEXT
    },
    "RecordingStudio.recordable_identifier" => {
      returns_kind: "Scalar",
      returns: "Primary key value, GlobalID string, or nil",
      notes: "Prefers recordable.id; falls back to the recordable GlobalID string.",
      example_response: <<~'TEXT'
        "9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef"
      TEXT
    },
    "RecordingStudio.recordable_global_id" => {
      returns_kind: "String",
      returns: "GlobalID string or nil",
      notes: "Returns a string GlobalID, not a GlobalID object.",
      example_response: <<~'TEXT'
        "gid://recording-studio/Workspace/1"
      TEXT
    },
    "RecordingStudio.recordable_name" => {
      returns_kind: "String",
      returns: "String",
      notes: "Returns the canonical display label for a recordable using recordable_name first, then engine fallbacks.",
      example_response: <<~'TEXT'
        "Report blue"
      TEXT
    },
    "RecordingStudio.recordable_type_label" => {
      returns_kind: "String",
      returns: "String",
      notes: "Returns the human-facing type label for a recordable instance, class, or type string.",
      example_response: <<~'TEXT'
        "Page"
      TEXT
    },
    "recording.name" => {
      returns_kind: "String",
      returns: "String",
      notes: "Returns the canonical display label for the recording's current recordable, falling back to the type label when necessary.",
      example_response: <<~'TEXT'
        "Report blue"
      TEXT
    },
    "recording.type_label" => {
      returns_kind: "String",
      returns: "String",
      notes: "Returns the human-facing type label for the recording's current recordable.",
      example_response: <<~'TEXT'
        "Page"
      TEXT
    },
    "recording.title" => {
      returns_kind: "String",
      returns: "String",
      notes: "Returns the recording's display title when distinct, otherwise the canonical display label.",
      example_response: <<~'TEXT'
        "Report blue"
      TEXT
    },
    "recording.summary" => {
      returns_kind: "String",
      returns: "String or nil",
      notes: "Returns a short display summary for the recording's current recordable when one is available.",
      example_response: <<~'TEXT'
        "A concise update for the activity feed."
      TEXT
    },
    "RecordingStudio.dup_strategy_for" => {
      returns_kind: "Strategy",
      returns: "Symbol, callable, or nil",
      notes: "Usually returns :dup or a configured callable for the recordable type.",
      example_response: <<~'TEXT'
        :dup
      TEXT
    },
    "RecordingStudio.duplicate_recordable" => {
      returns_kind: "Recordable",
      returns: "A duplicated recordable object",
      notes: "Returns the duplicated recordable snapshot, not a RecordingStudio::Recording wrapper.",
      example_response: <<~'TEXT'
        #<Page id: nil, title: "Quarterly Plan", persisted?: false>
      TEXT
    },
    "RecordingStudio.root_recording_for" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording",
      notes: "Finds or creates the top-level recording wrapper for the persisted root recordable.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "0d8e4d5a-d869-4cfe-bf13-f784b77d7f35", recordable_type: "Workspace", recordable_id: "46ce6659-3670-4f7e-9f17-d5ec4ff983d8">
      TEXT
    },
    "RecordingStudio.record!" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event",
      notes: "May return an existing event when idempotency deduplicates a retry.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "1f94e2f4-7a5d-4f4d-8f3c-3d5d7762c114", action: "created", recording_id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9">
      TEXT
    },
    "root_recording.record" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording",
      yields: "A new recordable instance before persistence",
      notes: "Returns the recording wrapper, not the yielded recordable object.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page", recordable_id: "9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef">
      TEXT
    },
    "root_recording.revise" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording",
      yields: "A duplicated recordable snapshot before persistence",
      notes: "Returns the recording wrapper after it points to the new recordable snapshot.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page", recordable_id: "c14b6f72-4c7f-4b6d-9d96-8f8d3e2c1b91">
      TEXT
    },
    "root_recording.log_event" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event",
      notes: "Appends an event for the target recording and returns that event object.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed", recording_id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9">
      TEXT
    },
    "recording.log_event!" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event",
      notes: "Logs an event on the current recording and returns the created event.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published", recording_id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9">
      TEXT
    },
    "root_recording.revert" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording",
      notes: "Returns the recording whose current recordable pointer was moved to the target snapshot.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page", recordable_id: "77d31f38-97bb-4a7a-8cb0-5d3ea6f5d125">
      TEXT
    },
    "root_recording.recordings_query" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers, not raw recordable models.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "8f21e57c-a6c4-4650-b7f9-451f64f2958f", recordable_type: "Page">
        ]>
      TEXT
    },
    "root_recording.recordings_of" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Filters the recordings relation by current recordable type.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">
        ]>
      TEXT
    },
    "root_recording.recording_for" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording or nil",
      notes: "Returns the recording wrapper for the given persisted recordable within the current root.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page", recordable_id: "9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef">
      TEXT
    },
    "root_recording.recordings_for" => {
      returns_kind: "Array",
      returns: "Array<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers for the provided persisted recordables in input order.",
      example_response: <<~'TEXT'
        [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "8f21e57c-a6c4-4650-b7f9-451f64f2958f", recordable_type: "Page">
        ]
      TEXT
    },
    "root_recording.recordables_of" => {
      returns_kind: "Array",
      returns: "Array<Recordable>",
      items: "Recordable",
      notes: "Returns current recordable models for the filtered recording wrappers under this root.",
      example_response: <<~'TEXT'
        [
          #<Page id: "9d1a4d5b-5f6a-4f0b-a7d4-2b4a4d0d12ef", title: "Quarterly Plan">,
          #<Page id: "c14b6f72-4c7f-4b6d-9d96-8f8d3e2c1b91", title: "Roadmap">
        ]
      TEXT
    },
    "root_recording.child_recordings_of" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns direct child recordings for the given parent recording, still constrained to the current root.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4", recordable_type: "Comment">
        ]>
      TEXT
    },
    "root_recording.events_query" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns a root-scoped event timeline filtered by the matching recordings and event attributes.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "root_recording.recordings_with_events" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns distinct recording wrappers whose event history matches the supplied event filters.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "8f21e57c-a6c4-4650-b7f9-451f64f2958f", recordable_type: "Page">
        ]>
      TEXT
    },
    "RecordingStudio::Recording.all" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers ordered by the model's default scope, newest updated first.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "8f21e57c-a6c4-4650-b7f9-451f64f2958f", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">
        ]>
      TEXT
    },
    "RecordingStudio::Recording.for_root" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers whose root_recording_id matches the given root recording.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "0d8e4d5a-d869-4cfe-bf13-f784b77d7f35", recordable_type: "Workspace">,
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">
        ]>
      TEXT
    },
    "RecordingStudio::Recording.of_type" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers whose current recordable type matches the provided class or type name.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">
        ]>
      TEXT
    },
    "recording.events" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns event rows for a single recording, newest first unless you reorder it.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "recording.latest_event" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event or nil",
      notes: "Returns the newest event for this recording using the default event ordering.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">
      TEXT
    },
    "recording.first_event" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event or nil",
      notes: "Returns the oldest event for this recording ordered by occurred_at and then created_at.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "1f94e2f4-7a5d-4f4d-8f3c-3d5d7762c114", action: "created">
      TEXT
    },
    "recording.event_by_idempotency_key" => {
      returns_kind: "Event",
      returns: "RecordingStudio::Event or nil",
      notes: "Returns the matching event for this recording when the idempotency key exists.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published", idempotency_key: "publish-page-7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9">
      TEXT
    },
    "recording.subtree_events" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns one merged event timeline for the current recording plus selected descendants, ordered newest first by occurred_at and then created_at. limit and offset apply to that combined ordered result, not per child recording.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.for_root" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events whose recordings belong to the given root recording, including descendants.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.for_recording" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events attached to a single recording wrapper.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.by_actor" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events performed by the given persisted actor.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.with_action" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events filtered to one action or a list of actions.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.recent" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events ordered newest first by occurred_at, then created_at.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">,
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "RecordingStudio::Event.by_impersonator" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events attributed to actions taken while impersonating as the given persisted actor.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "6e3e3b42-f0f7-4046-a20a-c3d8b69d1a6c", action: "published">
        ]>
      TEXT
    },
    "RecordingStudio::Event.between" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Event>",
      items: "RecordingStudio::Event",
      notes: "Returns events whose occurred_at timestamp falls within the given lower and upper bounds.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Event id: "2a7c59e6-73bc-4884-b4f0-93ee3d4b6ef2", action: "reviewed">
        ]>
      TEXT
    },
    "recording.parent_recording" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording or nil",
      notes: "Returns the immediate parent recording wrapper when one exists.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb", recordable_type: "Folder", recordable_id: "99ef1584-18da-42f4-98a4-9922633bf05b">
      TEXT
    },
    "recording.child_recordings" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns child recording wrappers, not child recordable models.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4", recordable_type: "Comment">
        ]>
      TEXT
    },
    "recording.root_recording_or_self" => {
      returns_kind: "Recording",
      returns: "RecordingStudio::Recording",
      notes: "Returns the root recording for descendants, or self when already on the root.",
      example_response: <<~'TEXT'
        #<RecordingStudio::Recording id: "0d8e4d5a-d869-4cfe-bf13-f784b77d7f35", recordable_type: "Workspace", recordable_id: "46ce6659-3670-4f7e-9f17-d5ec4ff983d8">
      TEXT
    },
    "recording.root?" => {
      returns_kind: "Boolean",
      returns: "true or false",
      notes: "Checks whether the current recording is the root node.",
      example_response: <<~'TEXT'
        true
      TEXT
    },
    "recording.leaf?" => {
      returns_kind: "Boolean",
      returns: "true or false",
      notes: "Checks whether the current recording has no child recordings.",
      example_response: <<~'TEXT'
        false
      TEXT
    },
    "recording.depth" => {
      returns_kind: "Integer",
      returns: "Integer",
      notes: "Counts ancestor recordings from the root down to the current node.",
      example_response: <<~'TEXT'
        3
      TEXT
    },
    "recording.level" => {
      returns_kind: "Integer",
      returns: "Integer",
      notes: "Alias for recording.depth.",
      example_response: <<~'TEXT'
        2
      TEXT
    },
    "recording.ancestors" => {
      returns_kind: "Array",
      returns: "Array<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Ordered from the root recording down to the direct parent.",
      example_response: <<~'TEXT'
        [
          #<RecordingStudio::Recording id: "0d8e4d5a-d869-4cfe-bf13-f784b77d7f35", recordable_type: "Workspace">,
          #<RecordingStudio::Recording id: "5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb", recordable_type: "Folder">
        ]
      TEXT
    },
    "recording.self_and_ancestors" => {
      returns_kind: "Array",
      returns: "Array<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Uses the same ancestor order, then appends the current recording at the end.",
      example_response: <<~'TEXT'
        [
          #<RecordingStudio::Recording id: "0d8e4d5a-d869-4cfe-bf13-f784b77d7f35", recordable_type: "Workspace">,
          #<RecordingStudio::Recording id: "5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb", recordable_type: "Folder">,
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">
        ]
      TEXT
    },
    "recording.descendants" => {
      returns_kind: "Array",
      returns: "Array<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns recording wrappers in parent-before-child traversal order.",
      example_response: <<~'TEXT'
        [
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4", recordable_type: "Comment">
        ]
      TEXT
    },
    "recording.descendant_ids" => {
      returns_kind: "Array",
      returns: "Array<String>",
      items: "String",
      notes: "Returns descendant recording ids in the same traversal order as recording.descendants.",
      example_response: <<~'TEXT'
        [
          "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9",
          "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4"
        ]
      TEXT
    },
    "recording.subtree_recordings" => {
      returns_kind: "Relation",
      returns: "ActiveRecord::Relation<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Returns a subtree relation, optionally including self and supporting scope or explicit ordering.",
      example_response: <<~'TEXT'
        #<ActiveRecord::Relation [
          #<RecordingStudio::Recording id: "5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb", recordable_type: "Folder">,
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4", recordable_type: "Comment">
        ]>
      TEXT
    },
    "recording.self_and_descendants" => {
      returns_kind: "Array",
      returns: "Array<RecordingStudio::Recording>",
      items: "RecordingStudio::Recording",
      notes: "Prepends the current recording, then follows with descendant recordings in traversal order.",
      example_response: <<~'TEXT'
        [
          #<RecordingStudio::Recording id: "5c0f9d52-5401-4cfa-af8b-dfb3c436d7cb", recordable_type: "Folder">,
          #<RecordingStudio::Recording id: "7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", recordable_type: "Page">,
          #<RecordingStudio::Recording id: "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4", recordable_type: "Comment">
        ]
      TEXT
    }
  }.freeze

  IDENTITY_METHOD_SUBTITLES = [
    "RecordingStudio.recordable_type_name",
    "RecordingStudio.resolve_recordable_type",
    "RecordingStudio.recordable_identifier",
    "RecordingStudio.recordable_global_id",
    "RecordingStudio.recordable_name",
    "RecordingStudio.recordable_type_label",
    "recording.name",
    "recording.type_label"
  ].freeze

  CRUD_METHOD_SUBTITLES = [
    "RecordingStudio.record!",
    "RecordingStudio.dup_strategy_for",
    "RecordingStudio.duplicate_recordable"
  ].freeze

  EVENT_METHOD_SUBTITLES = [
    "recording.log_event!",
    "recording.events",
    "recording.latest_event",
    "recording.first_event",
    "recording.event_by_idempotency_key",
    "recording.subtree_events",
    "RecordingStudio::Event.for_recording",
    "RecordingStudio::Event.by_actor",
    "RecordingStudio::Event.with_action",
    "RecordingStudio::Event.by_impersonator",
    "RecordingStudio::Event.between",
    "RecordingStudio::Event.recent"
  ].freeze

  QUERY_METHOD_SUBTITLES = [
    "RecordingStudio::Recording.all",
    "RecordingStudio::Recording.of_type",
    "RecordingStudio::Recording.for_root",
    "root_recording.recordings_query",
    "root_recording.recordings_of",
    "root_recording.recording_for",
    "root_recording.recordings_for",
    "root_recording.recordables_of",
    "root_recording.child_recordings_of",
    "root_recording.events_query",
    "root_recording.recordings_with_events",
    "RecordingStudio::Event.for_root",
    "RecordingStudio::Event.for_recording",
    "RecordingStudio::Event.by_actor",
    "RecordingStudio::Event.with_action",
    "RecordingStudio::Event.by_impersonator",
    "RecordingStudio::Event.between",
    "RecordingStudio::Event.recent",
    "recording.descendant_ids",
    "recording.subtree_recordings"
  ].freeze

  ROOT_METHOD_SUBTITLES = [
    "RecordingStudio.root_recording_for",
    "root_recording.record",
    "root_recording.revise",
    "root_recording.log_event",
    "root_recording.revert",
    "root_recording.recordings_query",
    "root_recording.recordings_of",
    "root_recording.recording_for",
    "root_recording.recordings_for",
    "root_recording.recordables_of",
    "root_recording.child_recordings_of",
    "root_recording.events_query",
    "root_recording.recordings_with_events",
    "RecordingStudio::Recording.for_root",
    "RecordingStudio::Event.for_root"
  ].freeze

  TREE_METHOD_CATALOG = [
    {
      title: "Read the Direct Parent",
      subtitle: "recording.parent_recording",
      code: <<~'RUBY'
        folder_recording = Recording.find(params[:id])

        parent = folder_recording.parent_recording

        # Returns the immediate parent as a RecordingStudio::Recording object.
        parent.id
        parent.name
      RUBY
    },
    {
      title: "Read Direct Children",
      subtitle: "recording.child_recordings",
      code: <<~'RUBY'
        page_recording = Recording.find(params[:id])

        children = page_recording.child_recordings

        # Returns a relation of RecordingStudio::Recording objects.
        children.map(&:id)
        children.map(&:name)
      RUBY
    },
    {
      title: "Jump to the Root Recording",
      subtitle: "recording.root_recording_or_self",
      code: <<~'RUBY'
        comment_recording = Recording.find(params[:id])

        # For roots this returns self; for descendants it returns the root.
        comment_recording.root_recording_or_self
      RUBY
    },
    {
      title: "Check Whether a Recording Is the Root",
      subtitle: "recording.root?",
      code: <<~'RUBY'
        root_recording.root?
        # => true

        child_recording.root?
        # => false
      RUBY
    },
    {
      title: "Check Whether a Recording Is a Leaf",
      subtitle: "recording.leaf?",
      code: <<~'RUBY'
        comment_recording.leaf?
        # => true when no child recordings exist
      RUBY
    },
    {
      title: "Measure Tree Depth",
      subtitle: "recording.depth",
      code: <<~'RUBY'
        comment_recording.depth
        # => 3 when the path is root -> folder -> page -> comment
      RUBY
    },
    {
      title: "Read the Level Alias",
      subtitle: "recording.level",
      code: <<~'RUBY'
        # level is an alias for depth.
        page_recording.level
      RUBY
    },
    {
      title: "Walk Up the Tree",
      subtitle: "recording.ancestors",
      code: <<~'RUBY'
        ancestors = comment_recording.ancestors

        # Returns RecordingStudio::Recording objects, not UUID strings or labels.
        ancestors.map(&:id)
        ancestors.map(&:name)
      RUBY
    },
    {
      title: "Include the Current Node When Walking Up",
      subtitle: "recording.self_and_ancestors",
      code: <<~'RUBY'
        lineage = page_recording.self_and_ancestors

        # Includes the current RecordingStudio::Recording object at the end.
        lineage.map(&:recordable_type_name)
      RUBY
    },
    {
      title: "Walk the Nested Subtree",
      subtitle: "recording.descendants",
      code: <<~'RUBY'
        descendants = folder_recording.descendants

        # Returns RecordingStudio::Recording objects in parent-before-child order.
        descendants.map(&:id)
        descendants.map(&:name)
      RUBY
    },
    {
      title: "Read Descendant IDs",
      subtitle: "recording.descendant_ids",
      code: <<~'RUBY'
        folder_recording.descendant_ids
        # => ["7d8d6e1d-3d4f-4f6c-9b72-5c1bb0d6a2c9", "41b7d1f8-8c17-47cc-951f-1f10d0f38ec4"]
      RUBY
    },
    {
      title: "Query the Subtree as a Relation",
      subtitle: "recording.subtree_recordings",
      code: <<~'RUBY'
        folder_recording.subtree_recordings(
          include_self: true,
          order: { updated_at: :desc }
        )
      RUBY
    },
    {
      title: "Include the Current Node When Walking Down",
      subtitle: "recording.self_and_descendants",
      code: <<~'RUBY'
        subtree = folder_recording.self_and_descendants

        # Includes the current RecordingStudio::Recording object first.
        subtree.map(&:recordable_type_name)
      RUBY
    }
  ].freeze

  def index
    specialized_method_subtitles = TREE_METHOD_CATALOG
      .map { |entry| entry.fetch(:subtitle) }
      .concat(CapabilitiesController::CAPABILITY_CATALOG.map { |entry| entry.fetch(:subtitle) })
      .concat(IDENTITY_METHOD_SUBTITLES)
      .concat(CRUD_METHOD_SUBTITLES)
      .concat(EVENT_METHOD_SUBTITLES)
      .concat(ROOT_METHOD_SUBTITLES)
      .concat(QUERY_METHOD_SUBTITLES)

    @method_catalog = decorate_catalog(METHOD_CATALOG.reject do |entry|
      specialized_method_subtitles.include?(entry.fetch(:subtitle))
    end)
  end

  def identity
    @method_catalog = decorate_catalog(catalog_for(IDENTITY_METHOD_SUBTITLES))
  end

  def crud
    @method_catalog = decorate_catalog(catalog_for(CRUD_METHOD_SUBTITLES))
  end

  def events
    @method_catalog = decorate_catalog(catalog_for(EVENT_METHOD_SUBTITLES))
  end

  def root
    @method_catalog = decorate_catalog(catalog_for(ROOT_METHOD_SUBTITLES))
  end

  def queries
    @method_catalog = decorate_catalog(catalog_for(QUERY_METHOD_SUBTITLES))
  end

  def tree
    @method_catalog = decorate_catalog(TREE_METHOD_CATALOG)
  end

  private

  def catalog_for(subtitles)
    subtitles.filter_map do |subtitle|
      METHOD_CATALOG.find { |entry| entry.fetch(:subtitle) == subtitle } ||
        TREE_METHOD_CATALOG.find { |entry| entry.fetch(:subtitle) == subtitle }
    end
  end

  def decorate_catalog(entries)
    entries.map do |entry|
      details = METHOD_RESPONSE_DETAILS.fetch(entry.fetch(:subtitle))
      entry.merge(details).merge(code: append_response_details(entry.fetch(:code), details))
    end
  end

  def append_response_details(code, details)
    [ code.chomp, response_details_comment_block(details) ].join("\n\n")
  end

  def response_details_comment_block(details)
    lines = []
    lines << "# Response"
    lines << "# Returns: #{details.fetch(:returns)}"
    lines << "# Type: #{details.fetch(:returns_kind)}" if details[:returns_kind].present?
    lines << "# Items: #{details.fetch(:items)}" if details[:items].present?
    lines << "# Yields: #{details.fetch(:yields)}" if details[:yields].present?
    lines << "# Notes: #{details.fetch(:notes)}" if details[:notes].present?
    if details[:example_response].present?
      lines << "# Example response:"
      details[:example_response].chomp.split("\n").each do |line|
        lines << "#   #{line}"
      end
    end
    lines.join("\n")
  end
end
