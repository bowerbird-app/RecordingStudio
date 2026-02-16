# RecordingStudio

RecordingStudio is a Rails engine foundation that implements Basecamp-style **Recordings**, **Recordables**, and **Events**
using `delegated_type`. It provides an append-only event timeline with polymorphic actors, a root recording API, and a
stable mixin surface for capabilities like comments, attachments, and reactions.

**Requirements:** Ruby 3.3+ and Rails 8.1+.

## Contents

- [Why RecordingStudio](#why-recordingstudio)
- [Naming Convention for Extensions](#naming-convention-for-extensions)
- [Recordable Table Names](#recordable-table-names)
- [Recordable Table Shape](#recordable-table-shape)
- [Installation](#installation)
- [Identity vs State vs History](#identity-vs-state-vs-history)
- [Data Model](#data-model)
- [Recording Hierarchy](#recording-hierarchy)
- [Delegated Type Registration](#delegated-type-registration)
- [Configuration](#configuration)
- [Root Recording API](#root-recording-api)
- [Actors](#actors)
- [Query API](#query-api)
- [Generators](#generators)
- [Instrumentation](#instrumentation)
- [Dummy Sandbox](#dummy-sandbox)
- [Testing Guidance](#testing-guidance)
- [Extension Philosophy](#extension-philosophy)
- [Glossary](#glossary)
- [Limitations](#limitations)
- [Access Control](#access-control)

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

## Recordable Table Names

Recordable models should use namespaced table names to avoid collisions with your app or other engines.
Prefix tables with `recording_studio_` so recordables are clearly scoped.

Examples:
- `RecordingStudio::Comment` -> `recording_studio_comments`
- `RecordingStudio::Page` -> `recording_studio_pages`

## Recordable Table Shape

Recordable tables should stay lean. Following the Basecamp approach, recordables are immutable snapshots, so there is
no need for `updated_at`. Keep only the columns required to represent the snapshot state, and put activity or metadata
on `Event` instead of expanding the recordable schema.

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
- Root recordings (often wrapping a top-level recordable like `Workspace`) own descendant recordings and provide the primary API.

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
  config.actor = -> { Current.actor }
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

## Root Recording API

Create a root `RecordingStudio::Recording` for your top-level recordable and call APIs on that root recording:

```ruby
class Workspace < ApplicationRecord
end
```

### Querying Recordings (Filters & Ordering)

`recordings_query` supports optional filters and ordering. For safety, **filters must be provided as a Hash, Relation, or Arel node**.
Raw SQL strings are ignored. Ordering is allowlisted to actual columns on the target model.

```ruby
# Filter by recordable attributes
root_recording.recordings_query(type: "Page", recordable_filters: { title: "Quarterly Plan" })

# Order by recordable attributes (sanitized to allowed columns)
root_recording.recordings_query(type: "Page", recordable_order: "title desc, created_at asc")

# Order recordings table columns (sanitized)
root_recording.recordings_query(order: "updated_at desc")
```

For advanced cases, pass a Relation/Arel node as `recordable_filters`.
`recordable_scope` should only be used with trusted, code-defined callables (never user-provided),
since it can inject arbitrary query logic.

### Record

Create a new recording (like `new`/`create`, but for recordings). This creates a new recordable snapshot and appends a `created` event.

```ruby
recording = root_recording.record(Page, actor: current_user) do |page|
  page.title = "Quarterly Plan"
  page.summary = "Initial snapshot"
end
```

To create a child recording under a parent:

```ruby
child = root_recording.record(Page, actor: current_user, parent_recording: recording)
```

### Revise

Create a new recording version (like `edit`/`update`, but for recordings). This creates a new recordable snapshot and appends an `updated` event.

```ruby
recording = root_recording.revise(recording, actor: current_user) do |page|
  page.title = "Updated title"
end
```

### Trash

Soft-delete a recording (similar to destroying, but for recordings).

```ruby
root_recording.trash(recording, actor: current_user)
```

You can also call `trash` on a recording instance:

```ruby
recording.trash(actor: current_user)
```

Trashing appends a terminal `trashed` event and soft-deletes the recording by setting `trashed_at`.

To hard delete (writes a `deleted` event), use `hard_delete`:

```ruby
root_recording.hard_delete(recording, actor: current_user)
```

To include child recordings, pass `include_children: true` or set `include_children = true`:

```ruby
RecordingStudio.configure do |config|
  config.include_children = true
end

root_recording.trash(recording, actor: current_user)
```

### Trash & Restore

Trash (soft delete) a recording and its children:

```ruby
root_recording.trash(recording, actor: current_user, include_children: true)
```

Or using the recording instance:

```ruby
recording.trash(actor: current_user, include_children: true)
```

Restore (un-trash) a recording and its children:

```ruby
root_recording.restore(recording, actor: current_user, include_children: true)
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
  root_recording: root_recording,
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

## Actors

Actors identify who performed an action. Events record a polymorphic actor (User, SystemActor, AI agent, etc.) so
your timeline can attribute activity to the right identity.

Actors referenced by events must be persisted records (the event stores `actor_type` + `actor_id`). That means
system actors live in the `system_actors` table and **must** have a row there to be referenced in events. You can
create them via seeds, migrations, or lazy creation on first use. A simple pattern for extensions is to keep a
configured name and `find_or_create_by!` the corresponding record when needed.

RecordingStudio expects your app to define `current_actor` and assign it to `Current.actor` in the application
controller. If you use Devise with a single actor, `current_actor` can just return `current_user`. If you support
multiple actor types, implement the selection logic inside `current_actor`.

Example in `ApplicationController`:

```ruby
class ApplicationController < ActionController::Base
  before_action :current_actor

  private

  def current_actor
    Current.actor = current_user
  end
end
```

With this setup, you can omit `actor:` when calling RecordingStudio APIs, and the configured `actor` will
use `Current.actor`.

### System Actors

System actors represent automated or non-human agents (background jobs, integrations, scheduled tasks). They are
stored as real records so events can attribute activity to a stable identity.

System actors must be persisted (the event stores `actor_type` + `actor_id`). Create them via seeds, migrations, or
lazy creation on first use. A simple pattern is to keep a configured name and `find_or_create_by!` the record:

```ruby
# e.g. db/seeds.rb
SystemActor.find_or_create_by!(name: "Automations")
```

When logging events, pass the system actor explicitly or set `Current.actor` to the system actor record in the
execution context.

### Impersonation

Impersonation lets an admin act “as” another user while preserving who the real actor was. RecordingStudio stores
both values: the event `actor` is the user being impersonated, and the `impersonator` is the admin who initiated the
impersonation.

If you use the Pretender gem, `current_user` returns the impersonated user and `true_user` returns the admin. You
can wire this into RecordingStudio by setting both `Current.actor` and `Current.impersonator`:

```ruby
class ApplicationController < ActionController::Base
  before_action :current_actor

  private

  def current_actor
    Current.actor = current_user
    Current.impersonator = respond_to?(:true_user) ? true_user : nil
  end
end
```

You can also pass `impersonator:` explicitly when calling RecordingStudio APIs. Either way, events will capture
both identities.

## Query API

### Recordings

| Query | Description |
| --- | --- |
| `root_recording.recordings_query` | Direct recordings for a root recording (excludes trashed items, newest first). |
| `root_recording.recordings_query(type: "Page")` | Recordings filtered by recordable type. |
| `root_recording.recordings_query(id: page.id)` | Recordings filtered by recordable ID. |
| `root_recording.recordings_query(parent_id: recording.id)` | Recordings filtered by parent recording. |
| `root_recording.recordings_query(created_after: 1.week.ago, created_before: Time.current)` | Recordings created in a time range. |
| `root_recording.recordings_query(updated_after: 1.week.ago, updated_before: Time.current)` | Recordings updated in a time range. |
| `root_recording.recordings_query(order: { updated_at: :asc })` | Recordings ordered by a recording column. |
| `root_recording.recordings_query(type: "Page", recordable_order: { score: :asc })` | Recordings ordered by recordable attributes. |
| `root_recording.recordings_query(type: "Page", recordable_filters: { topic: "Plans" })` | Recordings filtered by recordable attributes. |
| `root_recording.recordings_query(type: "Page", recordable_scope: ->(scope) { scope.where("topic ILIKE ?", "%Plans%") })` | Recordings filtered by a custom recordable scope. |
| `root_recording.recordings_query(limit: 50, offset: 100)` | Paginated recordings. |
| `root_recording.recordings_query(include_children: true)` | Recordings for a root recording (includes nested children). |
| `root_recording.recordings_query.trashed` | Trashed recordings for a root recording. |
| `root_recording.recordings_query.include_trashed` | Direct recordings for a root recording including trashed items. |
| `RecordingStudio::Recording.for_root(root_recording.id).trashed` | Trashed recordings for a root recording (scope-based). |
| `RecordingStudio::Recording.all` | Latest recordings first; excludes trashed recordings by default. |
| `RecordingStudio::Recording.including_trashed` | Includes both active and trashed recordings. |
| `RecordingStudio::Recording.trashed` | Trashed recordings only. |
| `RecordingStudio::Recording.for_root(root_recording.id)` | All recordings belonging to a root recording. |
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

Root Recordings can filter by recordable class:

```ruby
root_recording.recordings_of(Page)
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

The dummy app in `test/dummy` showcases the architecture with a `Workspace` root recording, `Page` recordables, and polymorphic
actors (`User`, `SystemActor`). It demonstrates:

- Recording creation, revisions, and unrecording via the root recording API
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
- **Root Recording**: Owner and API surface for recordings.

## Limitations

- No built-in UI; this gem focuses on the data and service layer.
- Storage growth is linear with history; plan retention policies accordingly.

## Access Control

RecordingStudio ships with two built-in recordables for access control:

### Access Recordable

`RecordingStudio::Access` stores a polymorphic actor and a role. Default roles
are **admin**, **edit**, and **view** (hierarchy: admin > edit > view).

- **Recording-level access**: create an Access recording as a child of the
  target recording (`parent_recording_id = target.id`).
- **Root-level access**: create an Access recording as a root recording
  under the root recording (`parent_recording_id = root_recording.id`).

```ruby
# Grant edit access on a specific recording
access = RecordingStudio::Access.create!(actor: user, role: :edit)
RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: access,
  parent_recording: page_recording
)

# Grant view access at the root level
access = RecordingStudio::Access.create!(actor: user, role: :view)
RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: access,
  parent_recording: root_recording
)
```

### AccessBoundary Recordable

`RecordingStudio::AccessBoundary` stops access inheritance up the recording
tree. An optional `minimum_role` allows role-based passthrough: access above
the boundary is allowed through only if the actor's role meets or exceeds the
minimum.

```ruby
# Create a boundary that blocks all inheritance
boundary = RecordingStudio::AccessBoundary.create!
RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: boundary,
  parent_recording: parent_recording
)

# Create a boundary that allows edit or higher to pass through
boundary = RecordingStudio::AccessBoundary.create!(minimum_role: :edit)
RecordingStudio::Recording.create!(
  root_recording: root_recording,
  recordable: boundary,
  parent_recording: parent_recording
)
```

### Access Resolution

Use `RecordingStudio::Services::AccessCheck` to check access:

```ruby
# Get the actor's role for a recording
role = RecordingStudio::Services::AccessCheck.role_for(actor: user, recording: recording)
# => :admin, :edit, :view, or nil

# Check if an actor has at least a given role
RecordingStudio::Services::AccessCheck.allowed?(actor: user, recording: recording, role: :edit)
# => true or false
```

#### Access API reference

| Method | Returns | What it does | How to use |
| --- | --- | --- | --- |
| `RecordingStudio::Services::AccessCheck.role_for(actor:, recording:)` | `:admin`, `:edit`, `:view`, or `nil` | Resolves an actor’s effective role for a specific recording, considering recording-level access, `AccessBoundary` rules, and root-level access. | `role = RecordingStudio::Services::AccessCheck.role_for(actor: user, recording: page_recording)` |
| `RecordingStudio::Services::AccessCheck.allowed?(actor:, recording:, role:)` | `true` / `false` | Authorization helper: checks whether the actor’s resolved role is at least the required role (admin > edit > view). | `RecordingStudio::Services::AccessCheck.allowed?(actor: user, recording: page_recording, role: :edit)` |
| `RecordingStudio::Services::AccessCheck.root_recordings_for(actor:, minimum_role: nil)` | `[root_recording_id, ...]` | Reverse-lookup: lists root recordings the actor has *root-level* access to via access recordings (`parent_recording_id = root_recording_id`). Recording-level access is intentionally excluded. | `RecordingStudio::Services::AccessCheck.root_recordings_for(actor: user, minimum_role: :view)` |
| `RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor:, minimum_role: nil)` | `[root_recording_id, ...]` | Same as `root_recordings_for` and returns root recording IDs for filtering queries (for example, then filter by root recordable type). | `ids = RecordingStudio::Services::AccessCheck.root_recording_ids_for(actor: user)` |
| `RecordingStudio::Services::AccessCheck.access_recordings_for(recording)` | `ActiveRecord::Relation<RecordingStudio::Recording>` | Helper scope: returns non-trashed access recordings directly under a recording (children where `recordable_type = "RecordingStudio::Access"`). This does not filter by actor; it’s mainly for inspection/debugging and tests. | `RecordingStudio::Services::AccessCheck.access_recordings_for(page_recording).includes(:recordable)` |
| `RecordingStudio::Access.roles` | `{ "view"=>0, "edit"=>1, "admin"=>2 }` | Enum mapping used for role ordering/comparisons (and for converting role symbols/strings to integer values). | `RecordingStudio::Access.roles.fetch("admin") # => 2` |
| `RecordingStudio::AccessBoundary.minimum_roles` | `{ "view"=>0, "edit"=>1, "admin"=>2 }` | Enum mapping for `AccessBoundary.minimum_role` thresholds (used when comparing whether a role can pass through a boundary). | `RecordingStudio::AccessBoundary.minimum_roles.fetch("edit") # => 1` |

---

The original template documentation lives in `docs/gem_template/` and remains as reference material.
