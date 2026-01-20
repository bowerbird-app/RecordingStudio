# ControlRoom

ControlRoom is a Rails engine foundation that implements Basecamp-style **Recordings**, **Recordables**, and **Events**
using `delegated_type`. It provides an append-only event timeline with polymorphic actors, a container-first API, and a
stable mixin surface for capabilities like comments, attachments, and reactions.

## Identity vs State vs History

| Layer | Model | Responsibility |
| --- | --- | --- |
| Identity | `Recording` | Stable handle for mixins and lifecycle operations |
| State | Recordable | Immutable, versioned snapshot of state |
| History | `Event` | Append-only timeline of activity |

Recordables are immutable snapshots. Recordings repoint to newer recordables. Events are append-only.

## Delegated Type Registration

ControlRoom uses `delegated_type` but cannot know your recordable classes ahead of time. Register types at runtime:

```ruby
ControlRoom.configure do |config|
  config.recordable_types = ["Page"]
end

ControlRoom.register_recordable_type("Page")
```

The engine applies `delegated_type` on boot and reload via a Railtie, and registration is idempotent.

## Configuration

```ruby
ControlRoom.configure do |config|
  config.recordable_types = []
  config.actor_provider = -> { Current.actor }
  config.instrumentation_enabled = true
  config.idempotency_mode = :return_existing # or :raise
  config.unrecord_mode = :soft # or :hard
  config.recordable_dup_strategy = :dup
end
```

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

Unrecording appends a terminal `deleted` event and soft-deletes the recording by default.

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

## Actor Model

Events capture polymorphic actors (User, ServiceAccount, AI agent, etc). Provide an actor provider if you do not pass
an actor explicitly.

## Query API

```ruby
ControlRoom::Recording.recent.kept
ControlRoom::Recording.for_container(workspace)
ControlRoom::Recording.of_type(Page)

ControlRoom::Event.for_recording(recording).recent
ControlRoom::Event.by_actor(current_user)
ControlRoom::Event.with_action("commented")
```

Containers can filter by recordable class:

```ruby
workspace.recordings_of(Page)
```

## Generators

```bash
rails g control_room:install
rails g control_room:migrations
```

The install generator creates the initializer and mounts the engine. The migrations generator installs the engine tables.

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

## Extension Philosophy

Recording is the capability surface. All mixins should use `recording.log_event!` and never write directly to `Event`.
Recordables are immutable; history is append-only.

---

The original template documentation lives in `docs/gem_template/` and remains as reference material.
