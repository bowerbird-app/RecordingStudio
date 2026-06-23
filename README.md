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
- [Quick Start: Root Recording Setup](#quick-start-root-recording-setup)
- [Identity vs State vs History](#identity-vs-state-vs-history)
- [Data Model](#data-model)
- [Recording Hierarchy](#recording-hierarchy)
- [Delegated Type Registration](#delegated-type-registration)
- [Labeling Recordables](#labeling-recordables)
- [Addon Author API Surface](#addon-author-api-surface)
- [Full API Reference for AI Agents](#full-api-reference-for-ai-agents)
- [Configuration](#configuration)
- [Upgrade Guide](#upgrade-guide)
- [Root Recording API](#root-recording-api)
- [Root Selection and Authorization](#root-selection-and-authorization)
- [Actors](#actors)
- [Query API](#query-api)
- [Generators](#generators)
- [Instrumentation](#instrumentation)
- [Dummy Sandbox](#dummy-sandbox)
- [Shared Default Layout](#shared-default-layout)
- [Testing Guidance](#testing-guidance)
- [Release Process](#release-process)
- [Extension Philosophy](#extension-philosophy)
- [Glossary](#glossary)
- [Limitations](#limitations)
- [Plugins / Addon Gems](#plugins--addon-gems)
- [Maintainer Docs](#maintainer-docs)

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

## Quick Start: Root Recording Setup

If you want a fast path for host gems/apps to start using RecordingStudio, use this minimal flow.

1. Define a top-level recordable (for example `Workspace`) and declare that it can be a root:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end
```

2. Define child recordables with their allowed parents:

```ruby
class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end
```

3. Ensure your app sets `Current.actor` (so APIs can infer actor automatically):

```ruby
class ApplicationController < ActionController::Base
  before_action :current_actor

  private

  def current_actor
    Current.actor = current_user
  end
end
```

4. Create/find the root recording for that top-level recordable:

```ruby
workspace = Workspace.find_or_create_by!(name: "Studio Workspace")

root_recording = RecordingStudio.root_recording_for(workspace)
```

5. Create your first recording under that root:

```ruby
recording = root_recording.record(Page) do |page|
  page.title = "Getting started"
end
```

At this point, you can use `root_recording.revise(...)`, `root_recording.log_event(...)`, and
`recording.log_event!(...)` for history-aware workflows.

## Identity vs State vs History

| Layer | Model | Responsibility |
| --- | --- | --- |
| Identity | `Recording` | Stable handle for mixins and lifecycle operations |
| State | Recordable | Immutable, versioned snapshot of state |
| History | `Event` | Append-only timeline of activity |

Recordables are immutable snapshots. Recordings repoint to newer recordables. Events are append-only.
Event timelines rely on `occurred_at` and `created_at`; `updated_at` is not required for event behavior.

## Data Model

- `Recording` holds identity and points at the current recordable snapshot.
- Recordings can form hierarchies via `parent_recording_id` (nullable).
- Recordables are immutable snapshots (versioned state).
- `Event` is the append-only timeline tied to a `Recording`.
- Root recordings (often wrapping a top-level recordable like `Workspace`) own descendant recordings and provide the primary API.

## Recording Hierarchy

Recordings can be arranged in a tree via `parent_recording_id`. Roots have `parent_recording_id = nil` and children
point at their parent recording. Use `recording.child_recordings` to traverse children.

For richer traversal, `RecordingStudio::Recording` also exposes:

```ruby
recording.parent_recording
recording.child_recordings
recording.root_recording_or_self
recording.root?
recording.parentless?
recording.orphan?
recording.leaf?
recording.depth
recording.level
recording.ancestors
recording.self_and_ancestors
recording.descendants
recording.self_and_descendants
```

`parentless?` checks for a blank `parent_recording_id`. `orphan?` is true when a recording is parentless but is not a
valid declared root. `ancestors` is ordered from the root recording down to the direct parent. `descendants` returns the
full nested subtree in parent-before-child order. These traversal helpers return `RecordingStudio::Recording` objects,
so callers can read `id`, `recordable_type`, `recordable_id`, `recordable_type_name`, or `name` from each returned node.

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
  config.recordable_types = ["Workspace", "Page"]
end

RecordingStudio.register_recordable_type("Workspace")
RecordingStudio.register_recordable_type("Page")

class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end
```

Each entry is an ActiveRecord model class name (as a String). RecordingStudio constantizes these names and registers them
with `delegated_type`, so the class must be loadable in your app.

The engine applies `delegated_type` on boot and reload via a Railtie, and registration is idempotent. By default,
configured ActiveRecord types must also declare their RecordingStudio hierarchy rules with
`recording_studio_recordable`.

`recording_studio_recordable` declares the hierarchy rules and display labels for a recordable type. `label:` is
required, `plural_label:` is optional and defaults to the pluralized label, and `root:` must be `true` or `false`.
Non-root recordables must provide `allowed_parent_types:`. Root recordables may also provide `allowed_parent_types: []`
to make it explicit that they are roots only and cannot be nested under another recording.

Root recordables can be top-level recordings. Non-root recordables must list allowed parents; an empty list is valid but
means the type cannot currently be recorded under any parent. `RecordingStudio.root_recording_for(recordable)` only
accepts recordables that declare `root: true`, and child creation checks `allowed_parent_types` before saving.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end
```

Useful declaration helpers:

```ruby
RecordingStudio.recordable_declaration_for("Page")
RecordingStudio.recordable_declaration_defined?("Page")
RecordingStudio.recordable_declarations
RecordingStudio.validate_recordable_declarations!
RecordingStudio.root_allowed?("Workspace")
RecordingStudio.root_recordable_type?("Workspace")
RecordingStudio.root_recordable_types
RecordingStudio.root_recordable_declarations
RecordingStudio.declared_parent_types_for("Page")
RecordingStudio.declared_allowed_parent_types_for("Page")
RecordingStudio.capability_parent_types_for("Comment")
RecordingStudio.capability_allowed_parent_types_for("Comment")
RecordingStudio.recordable_parent_allowances_for("Comment")
RecordingStudio.allowed_parent_types_for("Page")
RecordingStudio.child_recordable_types_for("Page")
RecordingStudio.parent_capabilities_for(child_type: "Comment", parent_type: "Page")
RecordingStudio.parent_allowed?(child_type: "Page", parent_recording: root_recording)
RecordingStudio.assert_root_allowed!("Workspace")
RecordingStudio.assert_parent_allowed!(child_type: "Page", parent_recording: root_recording)
```

Missing declarations raise `RecordingStudio::MissingRecordableDeclaration` by default. Invalid declarations or
unregistered `allowed_parent_types` raise `RecordingStudio::InvalidRecordableDeclaration`.

Normal domain recordables should continue to declare their native structural hierarchy with `allowed_parent_types:`.
Addon-owned internal children can instead be attached through capability registration:

```ruby
RecordingStudio.register_capability(
  :accessible,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)

class Page < ApplicationRecord
  include RecordingStudioAccessible::Accessible
end
```

The mixin should call `RecordingStudio.enable_capability(:accessible, on: name)`. Core then treats `Page` as an allowed
parent for `RecordingStudio::Access` without the addon knowing host-app parent types. Capability-derived parents are
unioned with declared parents for `allowed_parent_types_for`; use `declared_allowed_parent_types_for` to inspect only the
model declaration.

## Labeling Recordables

Recordable naming now lives in the engine, so callers can ask `RecordingStudio` or a `RecordingStudio::Recording`
for the current display `name` and `type_label` without re-implementing UI helper logic.

Host apps should put type labels in the declaration and can opt into custom instance names with `recordable_name`:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true

  def recordable_name
    name
  end
end
```

Preferred caller-facing helpers are:

```ruby
RecordingStudio.recordable_name(recordable)
RecordingStudio.recordable_type_label(recordable_or_type)
RecordingStudio.recordable_type_plural_label(recordable_or_type)

recording.name
recording.type_label
```

Resolution order for `RecordingStudio.recordable_name(recordable)` and `recording.name` is:

1. Registered `RecordingStudio::Labels` `name` formatter
2. `recordable.recordable_name`
3. `recordable.recording_studio_label` (deprecated compatibility alias)
4. Engine fallbacks: `title`, `name`, built-in comment formatting, then class-and-id
5. The type label fallback

`RecordingStudio::Labels.label_for(recordable)` and `recording.label` remain as compatibility aliases for
`recordable_name` and `name`.

`RecordingStudio.recordable_type_label(...)`, `RecordingStudio::Labels.type_label_for(...)`, and `recording.type_label`
use a registered `type_label` formatter first, then the declaration `label:`, then legacy model methods, the model's
human name, or a humanized class name. `RecordingStudio.recordable_type_plural_label(...)` uses the declaration
`plural_label:` when present and otherwise pluralizes the resolved type label.
`RecordingStudio::Labels.title_for(...)`, `RecordingStudio::Labels.summary_for(...)`, `recording.title`, and `recording.summary`
remain available for optional presentation metadata, but they are not the preferred identity surface.
Root recordings use the same APIs as any other recording because their names come from the root recordable.

## Addon Author API Surface

RecordingStudio core is now explicitly addon-first. Addons should prefer these public helpers instead of reimplementing
low-level type, root, duplication, or counter-cache logic.

### Public identity helpers

```ruby
RecordingStudio.recordable_type_name(recordable_or_type)
RecordingStudio.resolve_recordable_type(recordable_or_type)
RecordingStudio.recordable_identifier(recordable)
RecordingStudio.recordable_global_id(recordable)
RecordingStudio.recordable_name(recordable)
RecordingStudio.recordable_type_label(recordable_or_type)
RecordingStudio.recordable_type_plural_label(recordable_or_type)
```

`RecordingStudio::Recording` also exposes:

```ruby
recording.name
recording.type_label
```

### Public root/relationship helpers

```ruby
RecordingStudio.root_recording_for(recordable)
RecordingStudio.root_recording_or_self(recording)
RecordingStudio.root_recording_id_for(recording)
RecordingStudio.root_recording?(recording)
RecordingStudio.root_allowed?(recordable_or_type)
RecordingStudio.root_recordable_type?(recordable_or_type)
RecordingStudio.root_recordable_types
RecordingStudio.root_recordable_declarations
RecordingStudio.declared_parent_types_for(recordable_or_type)
RecordingStudio.declared_allowed_parent_types_for(recordable_or_type)
RecordingStudio.capability_parent_types_for(recordable_or_type)
RecordingStudio.capability_allowed_parent_types_for(recordable_or_type)
RecordingStudio.recordable_parent_allowances_for(recordable_or_type)
RecordingStudio.allowed_parent_types_for(recordable_or_type)
RecordingStudio.child_recordable_types_for(recordable_or_type)
RecordingStudio.parent_capabilities_for(child_type: "Page", parent_recording: recording)
RecordingStudio.parent_allowed?(child_type: "Page", parent_recording: recording)
RecordingStudio.assert_root_allowed!(recordable_or_type)
RecordingStudio.assert_recording_belongs_to_root!(root_recording, recording)
RecordingStudio.assert_root_recording!(recording)
RecordingStudio.assert_parent_recording_belongs_to_root!(parent_recording, root_recording)
RecordingStudio.assert_parent_allowed!(child_type: "Page", parent_recording: recording)
```

`RecordingStudio::Recording#root_recording_or_self` is the instance-level compatibility helper for addons that
previously used `root_recording || self`.

`RecordingStudio::Recording` also exposes tree traversal helpers for addon and host-app code:

```ruby
recording.root?
recording.parentless?
recording.orphan?
recording.leaf?
recording.depth
recording.level
recording.ancestors
recording.self_and_ancestors
recording.descendants
recording.self_and_descendants
```

`ancestors` returns `RecordingStudio::Recording` objects ordered from the root down to the direct parent.
`self_and_ancestors` appends the current recording object. `descendants` returns all nested child recording objects in
parent-before-child order, and `self_and_descendants` prepends the current recording.
`orphan?` identifies parentless recordings that are not valid declared roots.

### Public duplication/counter helpers

```ruby
RecordingStudio.duplicate_recordable(recordable)
RecordingStudio.update_polymorphic_counter("Page", page.id, :recordings_count, 1)
```

For trusted addon code, prefer explicit registration over monkey-patching:

```ruby
RecordingStudio.configure do |config|
  config.register_recordable_dup_strategy("Page") do |recordable|
    Page.new(title: recordable.title)
  end
end

RecordingStudio::Labels.register_formatter(
  "Page",
  name: ->(page) { page.title },
  type_label: ->(_page) { "Page" }
)
```

### Public vs internal boundaries

- **Public/stable for addons:** `RecordingStudio` helper methods above, `RecordingStudio::Labels`, and
  `RecordingStudio::Recording` identity/presentation helpers.
- **Trusted extension points only:** `config.register_recordable_dup_strategy`, `RecordingStudio::Labels.register_formatter`,
  `recordable_scope`, and the private `extend_recordings_query` hook. These should only be wired with code-defined
  callables, never user input.
- **Internal/private:** delegated type registrar internals, callback ordering, concern module layout, and direct mutation
  of counter caches outside the helper API.

## Full API Reference for AI Agents

For the complete public method surface, including arguments, return values, and the reason each method exists, use
[docs/API_REFERENCE.md](docs/API_REFERENCE.md).

That reference is the best starting point for AI agents and addon authors because it is organized by API surface:

- top-level `RecordingStudio` helpers
- configuration and hooks
- `RecordingStudio::Recording` write/query/tree methods
- event scopes
- labels, capabilities, duplication, and counter-cache helpers

### AI Write-Path Checklist

When an AI agent needs to write through RecordingStudio, use this sequence before guessing:

1. Normalize the type and declaration with `RecordingStudio.recordable_type_name(...)` and
  `RecordingStudio.recordable_declaration_for(...)`.
2. If the write is for a top-level object, confirm `RecordingStudio.root_allowed?(type)` and call
  `RecordingStudio.root_recording_for(persisted_recordable)`.
3. If the write is for a child, resolve the intended `parent_recording` first and verify
  `RecordingStudio.parent_allowed?(child_type:, parent_recording:)`.
4. If the child is capability-owned and its parents are derived from enablement, inspect
  `RecordingStudio.recordable_parent_allowances_for(...)` and
  `RecordingStudio.parent_capabilities_for(child_type:, parent_recording:)` to explain why the parent is valid.
5. Prefer the high-level entry points on `RecordingStudio::Recording` (`record`, `revise`, `log_event!`) and drop to
  `RecordingStudio.record!` only when you need the returned event object or lower-level control.

## Configuration

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = []
  config.require_recordable_declarations = true
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.impersonator }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing # or :raise (avoids duplicates when using idempotency keys; see below)
  config.recordable_dup_strategy = :dup
  config.register_recordable_dup_strategy("Page") { |recordable| Page.new(title: recordable.title) }
end
```

### Configuration Notes

- `recordable_types`: Array of delegated recordable class names. Use `register_recordable_type` for incremental runtime registration.
- `require_recordable_declarations`: Requires each configured ActiveRecord type to call
  `recording_studio_recordable`; set false only while migrating older apps, where missing declarations warn.
- `actor`: Callable used when callers omit `actor:` from write APIs.
- `impersonator`: Callable used when callers omit `impersonator:` from write APIs.
- `idempotency_mode`: Controls how duplicate `idempotency_key` values are handled. `:return_existing` returns the
  original event when the key matches, so retries are safe and do not create duplicates. `:raise` raises an error when
  the key matches, so callers must handle duplicates explicitly.
- `event_notifications_enabled`: Emits `recordings.event_created` ActiveSupport notifications when true.
- `instrumentation_enabled`: Compatibility alias for `event_notifications_enabled`.
- `recordable_dup_strategy`: `:dup` clones attributes on revision; you can supply a callable for custom duplication.
- `register_recordable_dup_strategy`: lets trusted addon code override duplication for one recordable type without
  changing the global fallback.
- `hooks`: Global hook registry exposed as `RecordingStudio.configuration.hooks`.

## Upgrade Guide

For existing apps upgrading to declaration-enforced roots and parent rules, see
[docs/UPGRADING.md](docs/UPGRADING.md). The short version is: add `recording_studio_recordable(...)` to every configured
ActiveRecord recordable, mark only true top-level types with `root: true`, declare `allowed_parent_types:` for child
types, and use `config.require_recordable_declarations = false` only as a temporary migration bridge.

## Root Recording API

Create a root `RecordingStudio::Recording` for your top-level recordable and call APIs on that root recording:

```ruby
class Workspace < ApplicationRecord
end
```

Preferred write helpers:

| Method | Takes | Returns | Use it when |
| --- | --- | --- | --- |
| `RecordingStudio.root_recording_for(workspace)` | persisted top-level recordable | root `RecordingStudio::Recording` | You need the root boundary for writes and queries. |
| `root_recording.record(Page, actor: ..., parent_recording: nil) { |page| ... }` | class or recordable instance, optional actor context, optional parent | `RecordingStudio::Recording` | You are creating a new recording and want a `created` event. |
| `root_recording.revise(recording, actor: ...) { |page| ... }` | existing recording plus changes | `RecordingStudio::Recording` | You are creating a new immutable snapshot and an `updated` event. |
| `root_recording.log_event(recording, action: ..., metadata: ...)` | target recording plus event fields | `RecordingStudio::Event` | You want history without changing the current snapshot. |
| `recording.log_event!(action: ..., metadata: ...)` | event fields | `RecordingStudio::Event` | Same as above when you already have the target recording. |
| `root_recording.revert(recording, to_recordable: previous_snapshot, actor: ...)` | recording and prior recordable snapshot | `RecordingStudio::Recording` | You need to move the recording back to a prior snapshot and log `reverted`. |
| `RecordingStudio.record!(...)` | low-level write parameters | `RecordingStudio::Event` | You need the canonical event-writing primitive directly. |

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

If an addon extends `recordings_query`, prefer the private `extend_recordings_query(scope)` hook. The older
`apply_recordings_query_extensions(scope)` name is still honored as a compatibility fallback.

Common root-level lookup helpers build on top of the same root scope:

```ruby
# Find one recording wrapper for a persisted recordable.
root_recording.recording_for(page)

# Find many recording wrappers in the input order.
root_recording.recordings_for([page, folder])

# Return raw current recordable models instead of recording wrappers.
root_recording.recordables_of(Page, include_children: true)

# Read direct children for a parent recording under the same root.
root_recording.child_recordings_of(folder_recording, type: Page)
```

For root-scoped history queries, use the event and touched-recording helpers:

```ruby
root_recording.events_query(actions: %w[published reviewed], type: Page)
root_recording.recordings_with_events(actions: "published", actor: current_user)
```

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

### Log Event Without Revising

Append an event without replacing the current recordable snapshot.

```ruby
event = recording.log_event!(
  action: "review_requested",
  actor: current_user,
  metadata: { reviewer_id: reviewer.id }
)
```

Use this for workflow transitions, comments, reactions, or audit-only actions where the current snapshot should stay the same.

### Revert

Point an existing recording back to a chosen recordable snapshot and append a `reverted` event.

```ruby
reverted = root_recording.revert(
  recording,
  to_recordable: old_snapshot,
  actor: current_user,
  metadata: { reason: "undo accidental change" }
)
```

`revert` returns the updated `RecordingStudio::Recording`, not the event.

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

## Root Selection and Authorization

RecordingStudio core no longer ships built-in access-control recordables, actor-based authorization services, or
device-session workspace persistence.

Core is responsible for recording state and history. Your host app or addon gem is responsible for:

- choosing the current root recording
- authorizing reads and writes
- handling workspace switching or per-device persistence

Minimal host app wiring:

```ruby
class ApplicationController < ActionController::Base
  before_action :current_actor

  private

  def current_actor
    Current.actor = current_user
  end
end

class PagesController < ApplicationController
  def create
    workspace = Workspace.find(params[:workspace_id])
    root_recording = RecordingStudio.root_recording_for(workspace)

    root_recording.record(Page, actor: Current.actor) do |page|
      page.title = params[:title]
    end
  end
end
```

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

The quick examples below are accurate for the current code, but the exhaustive method reference lives in
[docs/API_REFERENCE.md](docs/API_REFERENCE.md).

### Recordings

| Query | Description |
| --- | --- |
| `root_recording.recordings_query` | Direct recordings for a root recording (newest first). |
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
| `root_recording.recordings_with_children(type: Page, child_type: Comment)` | Parent recordings that have matching direct children. |
| `root_recording.recordings_with_descendants(type: Page, descendant_type: Comment)` | Ancestor recordings that have matching nested descendants. |
| `root_recording.recordings_without_children(type: Page, child_type: Comment)` | Parent recordings that do not have matching direct children. |
| `root_recording.recording_for(page)` | One recording wrapper for a persisted recordable in the current root. |
| `root_recording.recordings_for([page, folder])` | Recording wrappers for multiple persisted recordables, preserving input order. |
| `root_recording.recordables_of(Page, include_children: true)` | Raw current recordable models for the filtered recordings under the root. |
| `root_recording.child_recordings_of(folder_recording, type: Page)` | Direct child recordings for a parent recording under the same root. |
| `root_recording.events_query(actions: ["published"], type: "Page")` | Root-scoped event timeline filtered by recording and event attributes. |
| `root_recording.recordings_with_events(actions: ["published"], actor: current_user)` | Distinct recordings whose event history matches the filters. |
| `RecordingStudio::Recording.all` | Latest recordings first. |
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
| `recording.latest_event` | The newest event for a single recording. |
| `recording.first_event` | The oldest event for a single recording. |
| `recording.event_by_idempotency_key("publish-page-123")` | The matching event for a recording-scoped idempotency key. |
| `recording.subtree_events` | Events for the recording and all descendants, newest first. |
| `recording.subtree_events(descendant_scope: ->(scope) { scope.where(recordable_type: "Page") })` | Events for the recording plus selected descendant recordings. |
| `RecordingStudio::Event.for_root(root_recording)` | Events for a root recording and all descendant recordings. |
| `RecordingStudio::Event.by_actor(current_user)` | Events performed by a specific (polymorphic) actor. |
| `RecordingStudio::Event.by_impersonator(current_admin)` | Events performed while impersonating as a specific actor. |
| `RecordingStudio::Event.with_action("commented")` | Events with a specific action string. |
| `RecordingStudio::Event.between(2.days.ago, Time.current)` | Events whose occurred_at timestamps fall in a time range. |

Use `subtree_events` when you need a recording timeline that spans a branch of the tree without dropping the current
recording from the result set. `descendant_scope` receives a `RecordingStudio::Recording` relation for descendants only,
so you can keep the current recording's events while selectively including child recording types.

```ruby
page_recording.subtree_events(
  descendant_scope: ->(scope) { scope.where(recordable_type: "Page") },
  actions: %w[created published]
)
```

Root Recordings can filter by recordable class:

```ruby
root_recording.recordings_of(Page)
```

## Generators

```bash
rails g recording_studio:install
rails g recording_studio:migrations
```

The install generator mounts `RecordingStudio::Engine` at `/recording_studio`, creates the initializer, installs the
fresh-install migrations, and optionally adds `config/recording_studio.yml`. The mounted engine currently ships no
built-in browser UI or default routes, so treat that mount as integration surface area rather than a page to visit.
Use the dummy app for an interactive example.

The migrations generator installs the current core schema for fresh host apps.

If you are upgrading an older host app that previously depended on RecordingStudio's historical migration chain, use:

```bash
rails g recording_studio:migrations --full_history
```

That copies the full engine migration history, including legacy compatibility migrations kept for upgrade paths.

## Instrumentation

When `event_notifications_enabled` is `true`, the engine emits ActiveSupport notifications for record and event operations.
Subscribe with:

```ruby
ActiveSupport::Notifications.subscribe("recordings.event_created") do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.info("RecordingStudio: #{event.payload.inspect}")
end
```

## Dummy Sandbox

The dummy app in `test/dummy` showcases the architecture with `Workspace` root recordings, `Page` recordables, folders,
comments, and event history. It demonstrates:

- Recording creation, revisions, and nested content via the root recording API
- Event timeline with actors, recordables, and metadata
- Mixin-style event logging with `recording.log_event!`
- Explicit workspace-root page routes in the demo app, while RecordingStudio core stays focused on root recording primitives
- Simple browsing of workspaces, recordings, folders, and page history without built-in access management or hidden workspace switching

Run the sandbox:

```bash
cd test/dummy
bin/setup --skip-server
bundle exec rails tailwindcss:build
bin/dev
```

Open `http://localhost:3000/` for the dummy app home page. Useful demo routes include `/workspaces`, `/methods`, and
`/capabilities`.

## Shared Default Layout

RecordingStudio provides a reusable layout contract for addon gems at:

- `app/views/layouts/recording_studio/default_layout.html.erb`

Use `RecordingStudio::UsesDefaultLayout` in addon controllers to opt into this shell, then configure page nav metadata
with `RecordingStudio::LayoutHelper`.

Full usage details are documented in:

- `docs/layouts/default_layout.md`

## Testing Guidance

- Assert that recordables are immutable by verifying a new recordable was created on `revise`.
- Assert `Event` counts and actions, not direct model mutations.
- Assert recordable declarations for every configured type and cover root/parent rejection paths.
- Use `idempotency_key` in tests for retriable flows.

## Release Process

RecordingStudio uses automated semantic versioning on merges to `main` through Release Please.

- A Release PR is opened/updated automatically from merged changes.
- Merging the Release PR updates `lib/recording_studio/version.rb`, updates `CHANGELOG.md`, and creates a Git tag/release.
- Use Conventional Commits to drive version bumps:
  - `fix:` -> patch bump
  - `feat:` -> minor bump
  - `feat!:` or `BREAKING CHANGE:` footer -> major bump
- For breaking changes, include migration/upgrade notes in the PR description so release notes are actionable.

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

## Plugins / Addon Gems

RecordingStudio is designed as a core platform with optional capability addons.

Moveable behavior is no longer bundled in RecordingStudio. If your app needs that capability,
use the dedicated moveable addon instead of expecting built-in move APIs.

- `RecordingStudio::Recording` is the stable identity/lifecycle API surface.
- `recordable` is the delegated model that stores an immutable state snapshot.
- Recordable classes must be registered so delegated-type behavior works.
- Capability enablement is separate from recordable registration.

Registering a recordable means it can participate in recording/state behavior. It does **not**
automatically enable optional capability behavior.

### Registering recordable types (host app)

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace", "Page", "Folder"]
end

RecordingStudio.register_recordable_type("Workspace")
RecordingStudio.register_recordable_type("Page")
RecordingStudio.register_recordable_type("Folder")
```

### Capability mixins are explicit opt-in

A capability is enabled for a recordable type only when that model includes its mixin:

```ruby
class Page < ApplicationRecord
  include Capabilities::Reviewable.with(approval_class: "Approval")
end
```

This means:

- `Page` has that capability enabled.
- Other recordable types do **not** gain that capability unless they also include the mixin.
- Installing an addon gem does not silently enable behavior globally.

The mixin may come from your app or from an extracted addon gem namespace.

### Capability behavior is called on recordings

Mixins are included on the **recordable model**, but behavior is invoked on the corresponding
`RecordingStudio::Recording`:

```ruby
page_recording.capability_enabled?(:reviewable)
page_recording.capabilities
page_recording.capability_options(:reviewable)
```

You can also inspect capability state without a recording instance:

```ruby
RecordingStudio.capability_enabled?(:reviewable, for: Page)
RecordingStudio.capabilities_for(Page)
RecordingStudio.capability_options(:reviewable, for: Page)
```

### Capability mixin options configure behavior per recordable type

Capability mixins can accept parameters; they are not only on/off flags:

```ruby
class Page < ApplicationRecord
  include Capabilities::Reviewable.with(approval_class: "Approval")
end
```

`Page` will use the configured `Approval` recordable for addon-specific review behavior.

### Using addon gems in a host app

1. Add gems to your `Gemfile`.
2. `bundle install`.
3. Register recordable types.
4. Include addon mixins on specific recordable models.
5. Call capability behavior from `RecordingStudio::Recording`.

```ruby
gem "recording_studio"
```

### Core vs addon responsibilities

RecordingStudio core is responsible for:

- recordings / recordables / events
- delegated-type registration (`register_recordable_type`)
- capability registration/apply infrastructure (`register_capability`, `apply_capabilities!`)
- capability enablement + options lookup (`enable_capability`, `set_capability_options`, `capability_options`)
- capability-owned child recordable parent allowances
- shared guards/infrastructure (`RecordingStudio::Capability`, capability-disabled checks)

Addon gems are responsible for:

- defining capability-specific mixins and APIs
- registering capability behavior with RecordingStudio
- opting recordable types into capabilities via mixins
- defining and enforcing capability-specific rules/options
- logging capability-specific events through RecordingStudio recording/event APIs

### Building addon gems

Recommended integration sequence (works for extracted capabilities in general):

1. Addon gem defines capability code (recordable mixin + recording methods).
2. Addon gem registers capability metadata with `RecordingStudio.register_capability`.
   Use `recording_methods:` when the capability adds recording instance methods and `child_recordables:`
   when the capability owns child recordables whose parent allowances should be derived from enablement.
   Registered recording methods are automatically applied to `RecordingStudio::Recording`.
   `RecordingStudio.apply_capabilities!` remains available for explicit re-application in reloader/boot
   hooks, for example when your app/gem manually reloads capability constants during development.
3. Host app registers recordable types with RecordingStudio.
4. Host app includes addon mixins on specific recordable models.
5. RecordingStudio checks capability enablement/options by `recordable_type`.
6. Host app invokes capability behavior on `RecordingStudio::Recording`.

Useful helper methods on the recording surface:

- `recording.capability_enabled?(:reviewable)`
- `recording.capabilities`
- `recording.capability_options(:reviewable)`
- `recording.assert_capability!(:reviewable)`

## Custom / Extracted Capability Pattern (`reviewable` example)

The dummy app uses a concrete addon-style capability example as part of the same
plugin architecture story as extracted capabilities:

1. Provide a builder method that returns a recordable mixin (for example, `Reviewable.with(...)`).
2. Register capability metadata with
   `RecordingStudio.register_capability(:reviewable, RecordingMethods, source: "recording_studio_reviewable", child_recordables: ["Approval"])`.
3. In the mixin, opt specific recordable types in via `enable_capability`.
4. Store per-recordable configuration with `set_capability_options`.
5. Optionally register supporting recordable types when needed. Child-only recordables may omit
   `allowed_parent_types:` in their declaration when a registered capability derives those parent allowances.
6. Invoke behavior from the recording:

```ruby
class MyPage < ApplicationRecord
  include Capabilities::Reviewable.with(approval_class: "MyApproval")
end

recording.capability_enabled?(:reviewable)
recording.capabilities
recording.capability_options(:reviewable)
```

If a capability is not enabled for a recordable type, calling its recording method raises
`RecordingStudio::CapabilityDisabled`.

### Capability-owned child recordables

Addon gems that own internal child recordables should declare those children when registering the capability:

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

The recording-methods module is optional:

```ruby
RecordingStudio.register_capability(
  :accessible,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Whenever a host recordable enables `:accessible`, that host type becomes an allowed parent for
`RecordingStudio::Access`. The child recordable must still be registered, declare `recording_studio_recordable`, and be
non-root. `source:` is provenance metadata for debugging, validation, introspection, and conflict detection; it is not an
authentication boundary.

Useful introspection:

```ruby
RecordingStudio.capability_child_recordables_for(:accessible)
RecordingStudio.capability_allowed_parent_types_for("RecordingStudio::Access")
RecordingStudio.recordable_parent_allowances_for("RecordingStudio::Access")
RecordingStudio.declared_allowed_parent_types_for("RecordingStudio::Access")
RecordingStudio.allowed_parent_types_for("RecordingStudio::Access")
```

Capability-owned children grant only structural eligibility. They do not bypass addon authorization, role checks,
service-layer validation, deduplication, direct-creation guards, or root/parent hierarchy validation. No wildcard parent
allowance is introduced: only recordables that explicitly enable the capability become parents for that capability's
registered child recordables.

## Maintainer Docs

Public gem usage lives in this README, [docs/API_REFERENCE.md](docs/API_REFERENCE.md), and
[docs/UPGRADING.md](docs/UPGRADING.md).

Repository-maintainer workflows live in `docs/gem_template/`. The directory name is historical, but the files there are
maintainer docs for this repository's development environment, generators, and release workflow rather than alternate
public API documentation.
