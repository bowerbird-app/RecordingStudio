# ControlRoom

ControlRoom is a Rails engine foundation that implements Basecamp-style **Recordings**, **Recordables**, and **Events**
using `delegated_type`. It provides an append-only event timeline with polymorphic actors, a container-first API, and a
stable mixin surface for capabilities like comments, attachments, and reactions.

**Requirements:** Ruby 3.3+ and Rails 8.1+.

## Why ControlRoom

ControlRoom separates identity, state, and history so you can build durable collaboration features without mutating
history or coupling mixins to specific recordable models. It supports immutable snapshots, a stable capability surface,
and a consistent event timeline with polymorphic actors.

## Installation

Add the gem to your Gemfile:

```ruby
gem "control_room"
```

Install and set up:

```bash
bundle install
rails g control_room:install
rails g control_room:migrations
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

Workspace
└─ Page Recording (root)
  ├─ Comment Recording
  ├─ Comment Recording
  └─ Comment Recording

## Delegated Type Registration

ControlRoom uses `delegated_type` but cannot know your recordable classes ahead of time. Register types at runtime:

```ruby
ControlRoom.configure do |config|
  config.recordable_types = ["Page"]
end

ControlRoom.register_recordable_type("Page")
```

Each entry is an ActiveRecord model class name (as a String). ControlRoom constantizes these names and registers them
with `delegated_type`, so the class must be loadable in your app.

The engine applies `delegated_type` on boot and reload via a Railtie, and registration is idempotent.

## Configuration

```ruby
ControlRoom.configure do |config|
  config.recordable_types = []
  config.actor_provider = -> { Current.actor }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing # or :raise (avoids duplicates when using idempotency keys; see below)
  config.unrecord_mode = :soft # or :hard
  config.unrecord_children = true
  config.recordable_dup_strategy = :dup
  config.cascade_unrecord = ->(recording) { recording.child_recordings }
end
```

### Configuration Notes

- `idempotency_mode`: Controls how duplicate `idempotency_key` values are handled. `:return_existing` returns the
  original event when the key matches, so retries are safe and do not create duplicates. `:raise` raises an error when
  the key matches, so callers must handle duplicates explicitly.
- `unrecord_mode`: `:soft` keeps the recording (default) and marks it deleted; `:hard` removes it. This is a global
  setting (no per-call override).
- `unrecord_children`: When `true`, `unrecord` and `restore` will cascade to child recordings by default.
- `recordable_dup_strategy`: `:dup` clones attributes on revision; you can supply a callable for custom duplication.
- `cascade_unrecord`: Callable that returns child recordings to delete (defaults to `recording.child_recordings`).

## Container-First API

Include `ControlRoom::HasRecordingsContainer` in your container model:

```ruby
class Workspace < ApplicationRecord
  include ControlRoom::HasRecordingsContainer
end
```

### Record

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

```ruby
recording = workspace.revise(recording, actor: current_user) do |page|
  page.title = "Updated title"
end
```

### Unrecord

```ruby
workspace.unrecord(recording, actor: current_user)
```

Unrecording appends a terminal `deleted` event and soft-deletes the recording by default. Hard deletes are controlled
by `unrecord_mode` and are not configurable per call. If you need a one-off hard delete, destroy the recording
directly (no additional event is emitted):

```ruby
recording.destroy!
```

To cascade deletes to child recordings, pass `cascade: true` or set `unrecord_children = true`:

```ruby
ControlRoom.configure do |config|
  config.unrecord_children = true
  config.cascade_unrecord = ->(recording) { recording.child_recordings }
end

workspace.unrecord(recording, actor: current_user)
```

### Archive & Restore

Archive (soft delete) a recording and its children:

```ruby
workspace.unrecord(recording, actor: current_user, cascade: true)
```

Restore (un-archive) a recording and its children:

```ruby
workspace.restore(recording, actor: current_user, cascade: true)
```

Archive writes a `deleted` event and sets `discarded_at`. Restore writes a `restored` event and clears `discarded_at`.

### Idempotency Keys (Avoid duplicates)

Use `idempotency_key` to safely retry the *same* request without creating duplicates. Think of it as a dedupe key you
attach to an action. If the same key is seen again, ControlRoom treats it as a retry of the original request instead
of a new event.

Simple example: if a client retries a “comment” request due to a timeout, you can pass a stable key so ControlRoom
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
ControlRoom.record!(
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

ControlRoom::Recording.include(HasComments)
```

## Actor Model

Events capture polymorphic actors (User, ServiceAccount, AI agent, etc). Provide an actor provider if you do not pass
an actor explicitly.

```ruby
ControlRoom.configure do |config|
  config.actor_provider = -> { Current.actor }
end
```

## Query API

| Query | Description |
| --- | --- |
| `ControlRoom::Recording.recent` | Latest recordings first; excludes archived recordings by default. |
| `ControlRoom::Recording.with_archived` | Includes both active and archived recordings. |
| `ControlRoom::Recording.discarded` | Archived recordings only. |
| `ControlRoom::Recording.archived` | Alias for archived recordings only. |
| `ControlRoom::Recording.for_container(workspace)` | All recordings belonging to a container. |
| `ControlRoom::Recording.of_type(Page)` | Recordings whose current recordable is a given type. |
| `ControlRoom::Event.for_recording(recording).recent` | Events for a single recording, newest first. |
| `ControlRoom::Event.by_actor(current_user)` | Events performed by a specific (polymorphic) actor. |
| `ControlRoom::Event.with_action("commented")` | Events with a specific action string. |

Containers can filter by recordable class:

```ruby
workspace.recordings_of(Page)
```

### Archived vs Active

```ruby
ControlRoom::Recording.kept
ControlRoom::Recording.discarded
ControlRoom::Recording.archived
ControlRoom::Recording.with_archived
```

## Generators

```bash
rails g control_room:install
rails g control_room:migrations
```

The install generator creates the initializer and mounts the engine. The migrations generator installs the engine tables.

## Instrumentation

When `event_notifications_enabled` is `true`, the engine emits ActiveSupport notifications for record and event operations.
Subscribe with:

```ruby
ActiveSupport::Notifications.subscribe("control_room.record") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("ControlRoom: #{event.payload.inspect}")
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
