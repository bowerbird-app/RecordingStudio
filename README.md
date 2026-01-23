# RecordingStudio

RecordingStudio is a Rails engine foundation that implements Basecamp-style **Recordings**, **Recordables**, and **Events**
using `delegated_type`. It provides an append-only event timeline with polymorphic actors, a container-first API, and a
stable mixin surface for capabilities like comments, attachments, and reactions.

**Requirements:** Ruby 3.3+ and Rails 8.1+.

## Why RecordingStudio

RecordingStudio separates identity, state, and history so you can build durable collaboration features without mutating
history or coupling mixins to specific recordable models. It supports immutable snapshots, a stable capability surface,
and a consistent event timeline with polymorphic actors.

## Naming Convention for Extensions

Gems built on top of RecordingStudio should use the prefix **recording-studio-** followed by the feature name.

Examples:
- `recording-studio-pages`
- `recording-studio-comments`
- `recording-studio-attachments`

## Installation

Add the gem to your Gemfile:

```ruby
gem "recording_studio"
```

Install and set up:

```bash
bundle install
rails g recording_studio:install
rails g recording_studio:migrations
rails db:migrate
```

The install generator creates an initializer and mounts the engine routes.

## Identity vs State vs History

| Layer | Model | Responsibility |
| --- | --- | --- |
| Identity | `Recording` | Stable handle for mixins and lifecycle operations |
| State | Recordable | Immutable, versioned snapshot of state |
| History | `Event` | Append-only timeline of activity |

Recordables are immutable snapshots. Recordings repoint to newer recordables. Events are append-only.

## Data Model

- `Recording` holds identity and points at the current recordable snapshot.
- Recordings can form hierarchies via `parent_recording_id` (nullable).
- Recordables are immutable snapshots (versioned state).
- `Event` is the append-only timeline tied to a `Recording`.
- Containers (e.g., `Workspace`) own recordings and provide the primary API.

## Recording Hierarchy

Recordings can be arranged in a tree via `parent_recording_id`. Roots have `parent_recording_id = nil` and children
point at their parent recording. Use `recording.child_recordings` to traverse children.

Example hierarchy:

- Workspace
  - Page (recording)
    - Comment (recording)
    - Comment (recording)
    - Comment (recording)
## Delegated Type Registration

RecordingStudio uses `delegated_type` but cannot know your recordable classes ahead of time. Register types at runtime:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Page"]
end

RecordingStudio.register_recordable_type("Page")
```

Each entry is an ActiveRecord model class name (as a String). RecordingStudio constantizes these names and registers them
with `delegated_type`, so the class must be loadable in your app.

The engine applies `delegated_type` on boot and reload via a Railtie, and registration is idempotent.

## Configuration

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = []
  config.actor_provider = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing # or :raise (avoids duplicates when using idempotency keys; see below)
  # Include child recordings by default when trashing/restoring
  config.include_children = true
  config.recordable_dup_strategy = :dup
end
```

### Configuration Notes

- `idempotency_mode`: Controls how duplicate `idempotency_key` values are handled. `:return_existing` returns the
  original event when the key matches, so retries are safe and do not create duplicates. `:raise` raises an error when
  the key matches, so callers must handle duplicates explicitly.
- `include_children`: When `true`, `trash` and `restore` will include child recordings by default.
- `recordable_dup_strategy`: `:dup` clones attributes on revision; you can supply a callable for custom duplication.

## Container-First API

Include `RecordingStudio::HasRecordingsContainer` in your container model:

```ruby
class Workspace < ApplicationRecord
  include RecordingStudio::HasRecordingsContainer
end
```

### Record

Create a new recording (like `new`/`create`, but for recordings). This creates a new recordable snapshot and appends a `created` event.

```ruby
recording = workspace.record(Page, actor: current_user) do |page|
  page.title = "Quarterly Plan"
  page.summary = "Initial snapshot"
end
```

To create a child recording under a parent:

```ruby
child = workspace.record(Page, actor: current_user, parent_recording: recording)
```

### Revise

Create a new recording version (like `edit`/`update`, but for recordings). This creates a new recordable snapshot and appends an `updated` event.

```ruby
recording = workspace.revise(recording, actor: current_user) do |page|
  page.title = "Updated title"
end
```

### Trash

Soft-delete a recording (similar to destroying, but for recordings).

```ruby
workspace.trash(recording, actor: current_user)
```

You can also call `trash` on a recording instance:

```ruby
recording.trash(actor: current_user)
```

Trashing appends a terminal `trashed` event and soft-deletes the recording by setting `trashed_at`.

To hard delete (writes a `deleted` event), use `hard_delete`:

```ruby
workspace.hard_delete(recording, actor: current_user)
```

To include child recordings, pass `include_children: true` or set `include_children = true`:

```ruby
RecordingStudio.configure do |config|
  config.include_children = true
end

workspace.trash(recording, actor: current_user)
```

### Trash & Restore

Trash (soft delete) a recording and its children:

```ruby
workspace.trash(recording, actor: current_user, include_children: true)
```

Or using the recording instance:

```ruby
recording.trash(actor: current_user, include_children: true)
```

Restore (un-trash) a recording and its children:

```ruby
workspace.restore(recording, actor: current_user, include_children: true)
```

Trash writes a `trashed` event and sets `trashed_at`. Restore writes a `restored` event and clears `trashed_at`.

### Idempotency Keys (Avoid duplicates)

Use `idempotency_key` to safely retry the *same* request without creating duplicates. Think of it as a dedupe key you
attach to an action. If the same key is seen again, RecordingStudio treats it as a retry of the original request instead
of a new event.

Simple example: if a client retries a “comment” request due to a timeout, you can pass a stable key so RecordingStudio
does not create a second comment event.

```ruby
recording.log_event!(
  action: "commented",
  actor: current_user,
  metadata: { body: "Nice work!" },
  idempotency_key: "comment-#{comment.id}"
)
```

Behavior is controlled by `idempotency_mode`:
- `:return_existing` returns the original event when the key is reused (default retry-safe behavior).
- `:raise` raises an error when the key is reused (forces explicit duplicate handling).

If you don’t pass a key, every call creates a new event.

## Mixin / Capability Pipeline

Mixins attach to `Recording`. Use `recording.log_event!` to append events without creating a new recordable:

```ruby
recording.log_event!(action: "commented", actor: current_user, metadata: { body: "Nice work!" })
```

Idempotency keys are supported through `idempotency_key` and respect `idempotency_mode`.

## Service Layer

All entry points delegate to:

```ruby
RecordingStudio.record!(
  action: "created",
  recordable: page,
  recording: recording,
  container: workspace,
  actor: current_user
)
```

## Capabilities (Mixins)

Mixins should attach to `Recording` and emit events instead of writing to `Event` directly. Example:

```ruby
module HasComments
  def comment!(body:, actor:)
    log_event!(action: "commented", actor: actor, metadata: { body: body })
  end
end

RecordingStudio::Recording.include(HasComments)
```

## Actor Model

Events capture polymorphic actors (User, ServiceAccount, AI agent, etc). Provide an actor provider if you do not pass
an actor explicitly.

```ruby
RecordingStudio.configure do |config|
  config.actor_provider = -> { Current.actor }
end
```

## Query API

### Recordings

| Query | Description |
| --- | --- |
| `workspace.recordings` | Direct recordings for a container (excludes trashed items, newest first). |
| `workspace.recordings(type: "Page")` | Recordings filtered by recordable type. |
| `workspace.recordings(id: page.id)` | Recordings filtered by recordable ID. |
| `workspace.recordings(parent_id: recording.id)` | Recordings filtered by parent recording. |
| `workspace.recordings(created_after: 1.week.ago, created_before: Time.current)` | Recordings created in a time range. |
| `workspace.recordings(updated_after: 1.week.ago, updated_before: Time.current)` | Recordings updated in a time range. |
| `workspace.recordings(order: { updated_at: :asc })` | Recordings ordered by a recording column. |
| `workspace.recordings(type: "Page", recordable_order: { score: :asc })` | Recordings ordered by recordable attributes. |
| `workspace.recordings(type: "Page", recordable_filters: { topic: "Plans" })` | Recordings filtered by recordable attributes. |
| `workspace.recordings(type: "Page", recordable_scope: ->(scope) { scope.where("topic ILIKE ?", "%Plans%") })` | Recordings filtered by a custom recordable scope. |
| `workspace.recordings(limit: 50, offset: 100)` | Paginated recordings. |
| `workspace.recordings(include_children: true)` | Recordings for a container (includes nested children). |
| `workspace.recordings.trashed` | Trashed recordings for a container. |
| `workspace.recordings.include_trashed` | Direct recordings for a container including trashed items. |
| `RecordingStudio::Recording.for_container(workspace).trashed` | Trashed recordings for a container (scope-based). |
| `RecordingStudio::Recording.all` | Latest recordings first; excludes trashed recordings by default. |
| `RecordingStudio::Recording.including_trashed` | Includes both active and trashed recordings. |
| `RecordingStudio::Recording.trashed` | Trashed recordings only. |
| `RecordingStudio::Recording.for_container(workspace)` | All recordings belonging to a container. |
| `RecordingStudio::Recording.of_type(Page)` | Recordings whose current recordable is a given type. |

### Events

| Query | Description |
| --- | --- |
| `recording.events` | Events for a single recording, newest first. |
| `recording.events(actions: ["commented", "reverted"], actor: current_user)` | Events filtered by actions and actor. |
| `recording.events(actor_type: "User", actor_id: current_user.id)` | Events filtered by actor type and ID. |
| `recording.events(from: 2.days.ago, to: Time.current)` | Events within a time range. |
| `recording.events(limit: 50, offset: 100)` | Paginated events. |
| `RecordingStudio::Event.by_actor(current_user)` | Events performed by a specific (polymorphic) actor. |
| `RecordingStudio::Event.with_action("commented")` | Events with a specific action string. |

Containers can filter by recordable class:

```ruby
workspace.recordings_of(Page)
```

### Default scope and trashed

```ruby
RecordingStudio::Recording.all            # default scope: active only (excludes trashed)
RecordingStudio::Recording.trashed        # only trashed recordings
RecordingStudio::Recording.including_trashed # active + trashed recordings
```

## Generators

```bash
rails g recording_studio:install
rails g recording_studio:migrations
```

The install generator creates the initializer and mounts the engine. The migrations generator installs the engine tables.

## Instrumentation

When `event_notifications_enabled` is `true`, the engine emits ActiveSupport notifications for record and event operations.
Subscribe with:

```ruby
ActiveSupport::Notifications.subscribe("recording_studio.record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("RecordingStudio: #{event.payload.inspect}")
end
```

## Dummy Sandbox

The dummy app in `test/dummy` showcases the architecture with a `Workspace` container, `Page` recordables, and polymorphic
actors (`User`, `ServiceAccount`). It demonstrates:

- Recording creation, revisions, and unrecording via the container API
- Event timeline with actors, recordables, and metadata
- Mixin-style event logging with `recording.log_event!`

Run the sandbox:

```bash
cd test/dummy
bin/rails db:setup
bin/dev
```

## Testing Guidance

- Assert that recordables are immutable by verifying a new recordable was created on `revise`.
- Assert `Event` counts and actions, not direct model mutations.
- Use `idempotency_key` in tests for retriable flows.

## Extension Philosophy

Recording is the capability surface. All mixins should use `recording.log_event!` and never write directly to `Event`.
Recordables are immutable; history is append-only.

## Glossary

- **Recording**: Identity handle and capability surface.
- **Recordable**: Immutable snapshot of state.
- **Event**: Append-only historical entry.
- **Container**: Owner and API surface for recordings.

## Limitations

- No built-in UI; this gem focuses on the data and service layer.
- Storage growth is linear with history; plan retention policies accordingly.

---

The original template documentation lives in `docs/gem_template/` and remains as reference material.
