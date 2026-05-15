# RecordingStudio API Reference for AI Agents

This document is the authoritative, code-aligned reference for the public RecordingStudio API.
It is written for AI agents and addon authors who need to choose the correct entry point without
reverse-engineering the engine internals.

## Core Rules

- Treat `RecordingStudio::Recording` as the stable identity handle for a recordable's lifecycle.
- Treat the delegated `recordable` as an immutable snapshot of state.
- Treat `RecordingStudio::Event` as append-only history.
- Use a root recording as the write and query boundary for a workspace/project/thread tree.
- Prefer the documented helpers below over reaching into concerns, callbacks, or internals.

## Choose The Right Entry Point

Use this decision guide before calling methods:

- You have a top-level persisted model like `Workspace` and need its root recording:
  `RecordingStudio.root_recording_for(workspace)`
- You need to create a new snapshot under a root:
  `root_recording.record(Page) { |page| ... }`
- You need to update an existing recording by creating a new snapshot:
  `root_recording.revise(page_recording) { |page| ... }`
- You need to append history without changing the current snapshot:
  `recording.log_event!(action: "...")` or `root_recording.log_event(recording, action: "...")`
- You need one low-level write entry point that always returns the created event:
  `RecordingStudio.record!(...)`
- You need recordings under a root:
  `root_recording.recordings_query(...)`
- You need events under a root:
  `root_recording.events_query(...)`
- You need events for one recording only:
  `recording.events(...)`

## Top-Level Module: `RecordingStudio`

These methods are the main addon-facing API.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `configuration` | nothing | `RecordingStudio::Configuration` | Read or mutate engine configuration in one place. |
| `configure` | block with `config` | same configuration object | Standard Rails-style configuration entry point. |
| `registered_capabilities` | nothing | `Hash` | Introspection for capability registrations already applied to recordings. |
| `register_capability(name, mod)` | capability name, module | registered module map | Adds recording-level behavior from an addon without monkey-patching core. |
| `apply_capabilities!` | nothing | `Hash` of registrations iterated | Re-applies registered recording modules after reloads or boot order changes. |
| `register_recordable_type(name)` | class or class name | updated `recordable_types` and delegated-type registration side effect | Makes a recordable type available to delegated type resolution. |
| `recordable_type_name(recordable_or_type)` | instance, class, or class name | `String` or `nil` | Normalizes a recordable type to its class name. |
| `resolve_recordable_type(recordable_or_type)` | instance, class, or class name | class constant or `nil` | Safely resolves a recordable type for queries and addon wiring. |
| `recordable_identifier(recordable)` | recordable instance | record ID or global ID string or `nil` | Gives a stable identifier even when only a GlobalID is available. |
| `recordable_global_id(recordable)` | recordable instance | GlobalID string or `nil` | Produces a GlobalID string when the recordable supports it. |
| `recordable_name(recordable)` | recordable instance | `String` | Returns the display name used by recordings and UIs. |
| `recordable_type_label(recordable_or_type)` | instance, class, or class name | `String` | Returns a human-facing type label like `Page`. |
| `root_recording_for(recordable)` | persisted top-level recordable | `RecordingStudio::Recording` | Finds or creates the root recording for a top-level object. |
| `root_recording_or_self(recording)` | recording or root recording | `RecordingStudio::Recording` or `nil` | Collapses `root_recording || self` into one public helper. |
| `root_recording_id_for(recording)` | recording or root recording | root recording ID or `nil` | Returns the root boundary ID used by tree queries. |
| `root_recording?(recording)` | recording | `true` or `false` | Validates that a recording is the root of its tree. |
| `assert_recording_belongs_to_root!(root_recording, recording, message: ...)` | root recording, recording, optional message | `nil` or raises `ArgumentError` | Guards writes and queries from crossing root boundaries. |
| `assert_root_recording!(recording, message: ...)` | recording, optional message | `nil` or raises `ArgumentError` | Guards APIs that must receive a root recording. |
| `assert_parent_recording_belongs_to_root!(parent_recording, root_recording, message: ...)` | parent recording, root recording, optional message | `nil` or raises `ArgumentError` | Ensures new child recordings stay in the same tree. |
| `update_polymorphic_counter(recordable_or_type, recordable_id, column, delta)` | recordable type, ID, counter column, integer delta | `true` or `false` | Safely updates `recordings_count` or `events_count` style counters. |
| `dup_strategy_for(recordable_or_type)` | instance, class, or class name | callable or symbol | Resolves the duplication strategy used by `revise`. |
| `duplicate_recordable(recordable)` | recordable instance | duplicated recordable or `nil` | Duplicates a snapshot using the configured strategy. |
| `enable_capability(capability, on:)` | capability name, recordable type | configuration side effect | Enables a named capability for one recordable type. |
| `capability_enabled?(capability, for:)` | capability name, recordable type | `true` or `false` | Checks whether an addon capability is enabled. |
| `capabilities_for(recordable_or_type)` | instance, class, or class name | sorted `Array<Symbol>` | Lists enabled capabilities for a type. |
| `set_capability_options(capability, on:, **options)` | capability name, recordable type, option hash | configuration side effect | Stores per-type capability options. |
| `capability_options(capability, for: type)` | capability name, recordable type | `Hash` or `nil` | Reads per-type capability options. |
| `record!(action:, recordable:, recording: nil, root_recording: nil, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil, parent_recording: nil)` | write parameters | `RecordingStudio::Event` | Canonical low-level write API used by higher-level helpers. |

### `RecordingStudio.record!` parameter guidance

Use `RecordingStudio.record!` when you need the event object, or when a higher-level convenience method does not fit.

| Parameter | Required | Meaning |
| --- | --- | --- |
| `action:` | yes | Event action string such as `created`, `updated`, `commented`, `published`. |
| `recordable:` | yes | The current snapshot record. Saved automatically if needed. |
| `recording:` | no | Existing recording to update. Omit when creating a new recording. |
| `root_recording:` | yes unless `recording:` is supplied | Root tree boundary. Must itself be a root recording. |
| `actor:` | no | Explicit actor for the event. Falls back to configured actor lambda. |
| `impersonator:` | no | Explicit impersonator. Falls back to configured impersonator lambda. |
| `metadata:` | no | Arbitrary JSON-like hash stored on the event. `nil` is normalized to `{}`. |
| `occurred_at:` | no | Logical event timestamp. Defaults to `Time.current`. |
| `idempotency_key:` | no | Recording-scoped dedupe key for safe retries. |
| `parent_recording:` | no | Parent recording for a new child recording. Ignored when updating an existing recording. |

Behavior summary:

- When `recording:` is omitted, a new `RecordingStudio::Recording` is created.
- When `recording:` is present, the current recordable may be replaced, but its type cannot change.
- On success, the return value is always the new or reused `RecordingStudio::Event`.
- If `idempotency_key:` matches an existing event for the same recording, behavior depends on
  `config.idempotency_mode`.

## Configuration: `RecordingStudio::Configuration`

Use `RecordingStudio.configure` to access these settings.

| Setting or method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recordable_types` | nothing | `Array<String>` | Lists delegated recordable types currently registered. |
| `recordable_types=(types)` | array of classes or names | normalized array | Declares which recordable classes the engine should treat as delegated types. |
| `actor` | callable | callable | Supplies the default actor for writes when callers omit `actor:`. |
| `impersonator` | callable | callable | Supplies the default impersonator for writes when callers omit `impersonator:`. |
| `event_notifications_enabled` | boolean | boolean | Enables ActiveSupport event instrumentation. |
| `instrumentation_enabled` / `instrumentation_enabled=` | boolean | boolean | Compatibility alias for `event_notifications_enabled`. |
| `idempotency_mode` | `:return_existing` or `:raise` | symbol | Controls duplicate idempotency-key behavior. |
| `recordable_dup_strategy` | symbol or callable | symbol or callable | Global fallback duplication strategy used by `revise`. |
| `recordable_dup_strategies` | nothing | `Hash<String, callable>` | Introspection for per-type duplication overrides. |
| `hooks` | nothing | `RecordingStudio::Hooks` | Global hook registry for extension points. |
| `enable_capability(capability, on:)` | capability name, recordable type | internal set mutation | Enables a capability for one type. |
| `capability_enabled?(capability, for_type:)` | capability name, recordable type | `true` or `false` | Reads type-specific capability enablement. |
| `capabilities_for(recordable_or_type)` | instance, class, or class name | sorted `Array<Symbol>` | Returns enabled capabilities for a type. |
| `set_capability_options(capability, on:, **options)` | capability name, recordable type, options | stored options hash | Stores per-type addon options. |
| `capability_options(capability, for_type:)` | capability name, recordable type | `Hash` or `nil` | Reads per-type addon options. |
| `to_h` | nothing | serializable hash | Produces a summary of current configuration state. |
| `register_recordable_dup_strategy(type, callable = nil, &block)` | type and callable | stored callable | Overrides duplication for one recordable type. |
| `recordable_dup_strategy_for(recordable_or_type)` | instance, class, or class name | callable or symbol | Resolves the effective duplication strategy for a type. |
| `merge!(hash)` | hash-like object | merged configuration | Applies compatible keys from a hash, ignoring removed ones with a warning. |

Important behavior:

- `actor` defaults to `-> { Current.actor }` when `Current` exists.
- `impersonator` defaults to `-> { Current.impersonator }` when `Current` exists.
- `idempotency_mode = :return_existing` is retry-friendly and usually correct for HTTP or job retries.
- `recordable_dup_strategy = :dup` duplicates the recordable and clears known counter caches.

## Labels: `RecordingStudio::Labels`

Use this module when an addon needs recordable naming without duplicating UI heuristics.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `register_formatter(type, name: nil, type_label: nil, title: nil, summary: nil)` | recordable type and one or more callables | formatter registry mutation | Lets addons override display metadata for a type. |
| `formatters` | nothing | hash of formatter maps | Introspection and testing support. |
| `name_for(recordable)` | recordable instance | `String` | Preferred display name for the recordable. |
| `label_for(recordable)` | recordable instance | `String` | Compatibility alias for `name_for`. |
| `type_label_for(recordable_or_type)` | instance, class, or class name | `String` | Human-facing type label. |
| `title_for(recordable)` | recordable instance | `String` | Optional presentation title. |
| `summary_for(recordable)` | recordable instance | `String` or `nil` | Optional summary/body snippet. |

Resolution order for `name_for(recordable)`:

1. Registered `name` formatter
2. `recordable.recordable_name`
3. `recordable.recording_studio_label`
4. Heuristics: `title`, `name`, built-in comment snippet, class plus ID fallback
5. Explicit type label fallback

## Hooks: `RecordingStudio::Hooks`

Hooks are optional extension points for host apps and addons. Use them when you need lifecycle callbacks without
patching core classes.

### Instance API via `RecordingStudio.configuration.hooks`

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `before_initialize(handler = nil, priority: 100, &block)` | callable or block | registered hook | Run code before engine initialization tasks. |
| `after_initialize(handler = nil, priority: 100, &block)` | callable or block | registered hook | Run code after initialization tasks. |
| `on_configuration(handler = nil, priority: 100, &block)` | callable or block | registered hook | React to configuration application. |
| `before_service(handler = nil, priority: 100, &block)` | callable or block | registered hook | Observe service execution before it runs. |
| `after_service(handler = nil, priority: 100, &block)` | callable or block | registered hook | Observe service execution after it runs. |
| `around_service(handler = nil, priority: 100, &block)` | callable or block | registered hook | Wrap service execution around a block. |
| `on(event_name, handler = nil, priority: 100, &block)` | event name and callable or block | registered hook | Register any custom hook event. |
| `extend_model(model_name, &block)` | model name and module-style block | stored extension block | Add behavior to a named engine model extension point. |
| `extend_controller(controller_name, &block)` | controller name and module-style block | stored extension block | Add behavior to a named engine controller extension point. |
| `model_extensions_for(model_name)` | model name | `Array<Proc>` | Returns registered model extension blocks. |
| `controller_extensions_for(controller_name)` | controller name | `Array<Proc>` | Returns registered controller extension blocks. |
| `run(event_name, *args)` | event name and args | `Array` of hook results | Executes all hooks for an event in priority order. |
| `run_around(event_name, context, &block)` | event name, context, block | block result | Executes around hooks as a wrapper chain. |
| `registered?(event_name)` | event name | `true` or `false` | Checks whether hooks are registered. |
| `registered_counts` | nothing | hash of event names to counts | Introspection and debugging support. |
| `clear!` | nothing | cleared registries | Test helper to reset the registry. |
| `clear(event_name)` | event name | registry mutation | Removes hooks for one event. |

### Class API via `RecordingStudio::Hooks`

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `run(event_name, *args)` | event name and args | `Array` of results | Convenience proxy to the global hook registry. |
| `run_around(event_name, context, &block)` | event name, context, block | block result | Convenience proxy for around hooks. |
| `trigger(event_name, *args)` | event name and args | `Array` of results | Alias-style convenience method for custom events. |

## Recording API: `RecordingStudio::Recording`

This is the main object addons and host apps work with after they resolve a root.

### Class method

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `lock_ids!(ids)` | array-like list of IDs | locked `ActiveRecord::Relation` of recordings ordered by ID | Gives deterministic locking order to reduce deadlock risk. |

### Identity and presentation helpers

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recordable_type_name` | nothing | `String` or `nil` | Normalized class name for the current recordable. |
| `recordable_identifier` | nothing | recordable ID, GlobalID string, or `nil` | Stable identifier for routing and addon references. |
| `recordable_global_id` | nothing | GlobalID string or `nil` | Portable reference for persisted recordables. |
| `name` | nothing | `String` | Preferred display name for the current recordable snapshot. |
| `label` | nothing | `String` | Compatibility alias for `name`. |
| `type_label` | nothing | `String` | Human-facing type label for the current recordable type. |
| `title` | nothing | `String` | Optional presentation title. |
| `summary` | nothing | `String` or `nil` | Optional summary/body snippet. |

### Tree helpers

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `root?` | nothing | `true` or `false` | Checks whether this recording is a root recording. |
| `leaf?` | nothing | `true` or `false` | Checks whether this recording has no children. |
| `root_recording_or_self` | nothing | `RecordingStudio::Recording` | Returns the root recording boundary for this recording. |
| `ancestors` | nothing | `Array<RecordingStudio::Recording>` | Returns root-to-parent ancestry for tree navigation. |
| `self_and_ancestors` | nothing | `Array<RecordingStudio::Recording>` | Includes the current recording after its ancestors. |
| `descendants` | nothing | `Array<RecordingStudio::Recording>` | Returns the full descendant subtree in parent-before-child order. |
| `self_and_descendants` | nothing | `Array<RecordingStudio::Recording>` | Includes the current recording before descendants. |
| `depth` | nothing | `Integer` | Depth from the root recording. |
| `level` | nothing | `Integer` | Alias for `depth`. |
| `descendant_ids(include_self: false)` | include-self flag | `Array` of IDs | Returns descendant IDs without loading full objects in callers. |
| `subtree_recordings(include_self: true, order: nil, scope: nil)` | include-self flag, optional order, optional scope | `ActiveRecord::Relation<RecordingStudio::Recording>` | Builds a relation for the current subtree with stable default ordering. |

### Event helpers on a single recording

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)` | event filters | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads history for one recording. |
| `subtree_events(include_self: true, descendant_scope: nil, actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)` | subtree and event filters | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads history for this recording plus its descendants. |
| `latest_event` | nothing | `RecordingStudio::Event` or `nil` | Returns the newest event for this recording. |
| `first_event` | nothing | `RecordingStudio::Event` or `nil` | Returns the oldest event for this recording. |
| `event_by_idempotency_key(idempotency_key)` | idempotency key string | `RecordingStudio::Event` or `nil` | Finds a recording-scoped event retry key. |
| `log_event!(action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)` | event attributes | `RecordingStudio::Event` | Appends an event without replacing the current recordable snapshot. |

### Root-scoped write helpers

Call these on a root recording. They enforce that work stays inside that root tree.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `record(recordable_or_class, actor: nil, impersonator: nil, metadata: {}, parent_recording: nil) { |recordable| ... }` | class or recordable, optional write context, optional block | `RecordingStudio::Recording` | Creates a new recording and a `created` event. |
| `revise(recording, actor: nil, impersonator: nil, metadata: {}) { |recordable| ... }` | existing recording, optional context, optional block | `RecordingStudio::Recording` | Creates a new immutable snapshot and an `updated` event. |
| `log_event(recording = self, action:, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil)` | target recording plus event attributes | `RecordingStudio::Event` | Logs history for any recording under the same root. |
| `revert(recording, to_recordable:, actor: nil, impersonator: nil, metadata: {})` | recording and prior recordable snapshot | `RecordingStudio::Recording` | Repoints a recording to a chosen snapshot and logs a `reverted` event. |

Write behavior details:

- `record` accepts either a class like `Page` or a prebuilt recordable instance.
- `record` saves the recordable before calling `RecordingStudio.record!`.
- `revise` duplicates the current recordable using the configured duplication strategy.
- `revert` expects `to_recordable:` to be a compatible snapshot of the same recordable type.
- `log_event` and `log_event!` return the event, not the recording.

### Root-scoped query helpers

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recordings_query(include_children: false, type: nil, id: nil, parent_id: nil, created_after: nil, created_before: nil, updated_after: nil, updated_before: nil, order: nil, recordable_order: nil, recordable_filters: nil, recordable_scope: nil, limit: nil, offset: nil)` | recording and recordable filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Main read API for recordings under a root. |
| `recordings_of(recordable_class)` | class or class name | `ActiveRecord::Relation<RecordingStudio::Recording>` | Shortcut for `recordings_query(type: ...)`. |
| `recording_for(recordable)` | persisted recordable | `RecordingStudio::Recording` or `nil` | Finds one recording wrapper for a recordable in this root. |
| `recordings_for(recordables)` | array of persisted recordables | `Array<RecordingStudio::Recording>` | Batch version of `recording_for`, preserving input order. |
| `recordables_of(recordable_class, **options)` | recordable class plus query options | `Array<ActiveRecord::Base>` | Returns recordables instead of recording wrappers. |
| `child_recordings_of(parent_recording, **options)` | parent recording plus query options | `ActiveRecord::Relation<RecordingStudio::Recording>` | Reads direct children under the same root. |
| `events_query(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, limit: nil, offset: nil)` | root recording filters plus event filters | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads an event timeline for a root or subtree slice. |
| `recordings_with_events(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, order: nil, limit: nil, offset: nil)` | root recording filters plus event filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Finds recordings whose history matches event filters. |

Query guidance:

- `include_children: false` means direct children of the root only.
- `include_children: true` means the full root tree.
- `type:` should be a class or class name. It scopes both recording wrappers and recordable joins.
- `id:` filters by `recordable_id`, not by `recording.id`.
- `recording_id:` exists on `events_query` and `recordings_with_events` when you need to target one recording wrapper.
- `recordable_filters:` accepts a `Hash`, `ActiveRecord::Relation`, or Arel node.
- `recordable_scope:` must be trusted code. It receives a relation and may return a relation.
- `order:` is sanitized against recording columns.
- `recordable_order:` is sanitized against recordable columns for the resolved `type:`.

## Capability Helper API: `RecordingStudio::Capability`

Recording objects include this concern automatically.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `assert_capability!(name, for_type: recordable_type)` | capability name and optional type | `nil` or raises `RecordingStudio::CapabilityDisabled` | Guards capability-specific methods. |
| `capability_enabled?(name, for_type: recordable_type)` | capability name and optional type | `true` or `false` | Checks capability availability from a recording instance. |
| `capability_options(name, for_type: recordable_type)` | capability name and optional type | `Hash` or `nil` | Reads per-type capability configuration. |
| `capabilities(for_type: recordable_type)` | optional type | sorted `Array<Symbol>` | Lists enabled capabilities on the type behind the recording. |

## Event API: `RecordingStudio::Event`

The event model is intentionally small. Most public usage is through scopes.

| Method or scope | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `for_recording(recording)` | recording | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads events for one recording. |
| `for_root(root_recording_or_id)` | root recording or ID | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads events across a full root tree. |
| `by_actor(actor)` | persisted polymorphic actor | `ActiveRecord::Relation<RecordingStudio::Event>` | Filters by actor identity. |
| `by_impersonator(impersonator)` | persisted polymorphic impersonator | `ActiveRecord::Relation<RecordingStudio::Event>` | Filters by impersonator identity. |
| `with_action(action)` | action string or array | `ActiveRecord::Relation<RecordingStudio::Event>` | Filters by action name. |
| `between(from_time = nil, to_time = nil)` | from and to times | `ActiveRecord::Relation<RecordingStudio::Event>` | Filters by `occurred_at` range. |
| `recent` | nothing | `ActiveRecord::Relation<RecordingStudio::Event>` | Orders by newest logical event first. |

## Counter And Duplication Helpers

These are stable helpers for trusted addon code.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `RecordingStudio.duplicate_recordable(recordable)` | recordable instance | duplicated recordable or `nil` | Uses the configured strategy instead of open-coding duplication. |
| `RecordingStudio::Duplication.reset_counter_caches(recordable)` | recordable instance | same recordable or `nil` | Resets `recordings_count` and `events_count` on duplicates. |
| `RecordingStudio.update_polymorphic_counter(recordable_or_type, recordable_id, column, delta)` | type, ID, column, delta | `true` or `false` | Public wrapper around safe counter-cache updates. |

## Typical Usage Patterns

### Create a root and first page

```ruby
workspace = Workspace.find_or_create_by!(name: "Studio")
root = RecordingStudio.root_recording_for(workspace)

page_recording = root.record(Page, actor: Current.actor) do |page|
  page.title = "Getting started"
  page.summary = "Initial snapshot"
end
```

### Revise a page

```ruby
updated_recording = root.revise(page_recording, actor: Current.actor) do |page|
  page.title = "Getting started v2"
end
```

### Log a workflow event without changing the snapshot

```ruby
event = page_recording.log_event!(
  action: "review_requested",
  actor: Current.actor,
  metadata: { reviewer_id: reviewer.id }
)
```

### Query pages and recent publishing activity under a root

```ruby
pages = root.recordings_query(type: Page, include_children: true)

publish_events = root.events_query(
  type: Page,
  actions: %w[published unpublished],
  from: 7.days.ago
)
```

## What Not To Depend On

These details are intentionally internal and should not be treated as stable addon API:

- concern file layout
- callback ordering details
- direct mutation of recording or event counter caches outside the helpers above
- delegated type registrar internals
- private query helper methods such as sanitizers and scope builders

If you need behavior that is not covered by this reference, prefer adding a new public helper rather than reaching into
private internals.