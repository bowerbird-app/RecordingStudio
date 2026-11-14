# RecordingStudio API Reference for AI Agents

This document is the authoritative, code-aligned reference for the public RecordingStudio API.
It is written for AI agents and addon authors who need to choose the correct entry point without
reverse-engineering the engine internals.

## Core Rules

- Treat `RecordingStudio::Recording` as the stable identity handle for a recordable's lifecycle.
- Treat the delegated `recordable` as an immutable snapshot of state.
- Treat `RecordingStudio::Event` as append-only history.
- Use a root recording as the write and query boundary for a workspace/project/thread tree.
- Declare every configured ActiveRecord recordable with `recording_studio_recordable(...)`; declarations define type
  labels, root eligibility, and allowed parent types.
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
- You are changing a recording's parent or root:
  `RecordingStudio.lock_for_move!(recording, to_parent:, to_root:)` inside that transaction
- You need recordings under a root:
  `root_recording.recordings_query(...)`
- You need recordings based on direct child or nested descendant presence:
  `root_recording.recordings_with_children(...)`, `root_recording.recordings_with_descendants(...)`, or
  `root_recording.recordings_without_children(...)`
- You need events under a root:
  `root_recording.events_query(...)`
- You need events for one recording only:
  `recording.events(...)`

## AI Hierarchy And Write Checklist

When an AI agent needs to create or revise data, validate the hierarchy first instead of inferring it from naming:

1. Normalize the type with `RecordingStudio.recordable_type_name(...)`.
2. Read the declaration with `RecordingStudio.recordable_declaration_for(...)`.
3. For top-level writes, require a persisted recordable, confirm `RecordingStudio.root_allowed?(...)`, then call
  `RecordingStudio.root_recording_for(...)`.
4. For child writes, resolve the intended `parent_recording` in the same root tree and check
  `RecordingStudio.parent_allowed?(child_type:, parent_recording:)` before writing.
5. If the child is capability-owned and does not list all parents directly, inspect
  `RecordingStudio.recordable_parent_allowances_for(...)`,
  `RecordingStudio.capability_parent_types_for(...)`, and
  `RecordingStudio.parent_capabilities_for(child_type:, parent_recording:)` to explain the relationship.
6. Prefer `root_recording.record`, `root_recording.revise`, and `recording.log_event!`; use
  `RecordingStudio.record!` only when you need the returned event object or lower-level control.
7. Writes fail closed. Set `config.authorize_write` and supply an actor. A missing authorizer raises
  `RecordingStudio::AuthorizationError`. A missing actor raises `RecordingStudio::ActorRequired`.
  Set `config.allow_unauthorized_writes = true` only to keep the old open writes.

## Top-Level Module: `RecordingStudio`

These methods are the main addon-facing API.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `configuration` | nothing | `RecordingStudio::Configuration` | Read or mutate engine configuration in one place. |
| `configure` | block with `config` | same configuration object | Standard Rails-style configuration entry point. |
| `register_gate(gate_name, check_name, callable = nil, priority: 100, &block)` | gate name, check name, callable or block, optional priority | normalized check name | Adds one named check. The same gate and check name replaces the previous check and logs a warning. |
| `unregister_gate(gate_name, check_name)` | gate name, check name | `true` when removed, otherwise `false` | Removes one named check. |
| `gate_registered?(gate_name)` | gate name | `true` or `false` | Reports whether any check is registered for that gate, including checks a host has disabled. |
| `gate_checks(gate_name)` | gate name | array of frozen hashes `{ name:, priority:, enabled: }` | Lists the gate's checks in the order `check_gate` runs them. |
| `check_gate(gate_name, actor:, recording: nil, **context)` | gate name, required `actor:`, optional `recording:`, extra keywords | `RecordingStudio::GateDecision` | Runs enabled checks. Returns allow, or the first deny. |
| `registered_capabilities` | nothing | `Hash` | Introspection for capability registrations, including source and child-recordable metadata. |
| `register_capability(name, mod = nil, recording_methods: nil, source: nil, child_recordables: [])` | capability name plus optional recording methods and child recordables | registered capability metadata | Adds recording-level behavior and/or source-aware capability-owned child-recordable metadata without monkey-patching core. |
| `apply_capabilities!` | nothing | `Hash` of registrations iterated | Re-applies registered recording modules after reloads or boot order changes. |
| `register_recordable_type(name)` | class or class name | updated `recordable_types` and delegated-type registration side effect | Makes a recordable type available to delegated type resolution. |
| `recordable_type_name(recordable_or_type)` | instance, class, or class name | `String` or `nil` | Normalizes a recordable type to its class name. |
| `resolve_recordable_type(recordable_or_type)` | instance, class, or class name | class constant or `nil` | Safely resolves a recordable type for queries and addon wiring. |
| `recordable_identifier(recordable)` | recordable instance | record ID or global ID string or `nil` | Gives a stable identifier even when only a GlobalID is available. |
| `recordable_global_id(recordable)` | recordable instance | GlobalID string or `nil` | Produces a GlobalID string when the recordable supports it. |
| `recordable_name(recordable)` | recordable instance | `String` | Returns the display name used by recordings and UIs. |
| `recordable_type_label(recordable_or_type)` | instance, class, or class name | `String` | Returns a human-facing type label like `Page`. |
| `recordable_type_plural_label(recordable_or_type)` | instance, class, or class name | `String` | Returns the declared plural label or pluralized type label for a type. |
| `recordable_declaration_for(type)` | instance, class, or class name | declaration or `nil` | Reads the `recording_studio_recordable` declaration. |
| `recordable_declaration_defined?(type)` | instance, class, or class name | `true` or `false` | Checks whether a type declared RecordingStudio rules. |
| `recordable_declarations` | nothing | duplicate `Hash<String, Declaration>` | Introspects the currently loaded declarations without exposing the mutable registry. |
| `validate_recordable_declarations!` | nothing | `true` or raises | Ensures configured ActiveRecord recordable types have valid declarations. |
| `declared_parent_types_for(type)` / `declared_allowed_parent_types_for(type)` | instance, class, or class name | `Array<String>` | Reads parent types declared directly on the recordable declaration. |
| `allowed_parent_types_for(type)` | instance, class, or class name | `Array<String>` | Reads the effective parent allowlist, including capability-derived parent types. |
| `capability_child_recordables_for(capability)` | capability name | `Array<String>` | Lists child recordables declared for a registered capability. |
| `capability_parent_types_for(type)` / `capability_allowed_parent_types_for(type)` | instance, class, or class name | `Array<String>` | Lists parent types granted by capability registrations and enablement. |
| `recordable_parent_allowances_for(type)` | instance, class, or class name | frozen `Hash<String, Array<String>>` | Lists capability-derived parent allowances grouped by source/provenance. |
| `child_recordable_types_for(type)` | instance, class, or class name | `Array<String>` | Lists capability-owned child recordable types enabled for a parent type. |
| `parent_capabilities_for(child_type:, parent_recording: nil, parent_type: nil)` | child type plus parent recording or type | `Array<Symbol>` | Explains which capabilities allow a given parent/child relationship. |
| `root_allowed?(type)` | instance, class, or class name | `true`, `false`, or raises | Checks whether a recordable type may be saved as a root. |
| `root_recordable_type?(type)` | instance, class, or class name | `true`, `false`, or raises | Alias-style helper for `root_allowed?`. |
| `root_recordable_types` | nothing | `Array<String>` or raises | Lists configured recordable types allowed as roots. |
| `root_recordable_declarations` | nothing | `Array<Declaration>` | Lists configured declarations whose types declare `root: true`. |
| `shared_root_type?(type)` | instance, class, or class name | `true` or `false` | Checks whether a recordable type is a shared root. |
| `shared_root_types` | nothing | `Array<String>` | Lists configured shared root types. |
| `shared_root_declarations` | nothing | `Array<Declaration>` | Lists configured shared root declarations. |
| `parent_allowed?(child_type:, parent_recording:)` | child type, parent recording | `true`, `false`, or raises | Checks declared and capability-derived parent/child hierarchy rules. |
| `assert_root_allowed!(type)` | instance, class, or class name | `true` or raises `RecordingStudio::RootNotAllowed` | Guards APIs that create or identify root recordings. |
| `assert_parent_allowed!(child_type:, parent_recording:)` | child type, parent recording | `true` or raises `RecordingStudio::InvalidParent` | Guards child creation against declaration and capability-derived hierarchy rules. |
| `root_recording_for(recordable)` | persisted top-level recordable | `RecordingStudio::Recording` | Finds or creates the root recording for a top-level object. |
| `root_recording_or_self(recording)` | recording or root recording | `RecordingStudio::Recording` or `nil` | Collapses `root_recording || self` into one public helper. |
| `root_recording_id_for(recording)` | recording or root recording | root recording ID or `nil` | Returns the root boundary ID used by tree queries. |
| `root_recording?(recording)` | recording | `true` or `false` | Validates that a recording is the root of its tree. |
| `shared_root?(recording)` | recording | `true` or `false` | Checks whether this recording is a shared root node. |
| `shared_root_tree?(recording)` | recording | `true` or `false` | Checks whether this recording lives under a shared root. |
| `assert_recording_belongs_to_root!(root_recording, recording, message: ...)` | root recording, recording, optional message | `nil` or raises `ArgumentError` | Guards writes and queries from crossing root boundaries. |
| `assert_root_recording!(recording, message: ...)` | recording, optional message | `nil` or raises `ArgumentError` | Guards APIs that must receive a root recording. |
| `assert_parent_recording_belongs_to_root!(parent_recording, root_recording, message: ...)` | parent recording, root recording, optional message | `nil` or raises `ArgumentError` | Ensures new child recordings stay in the same tree. |
| `update_polymorphic_counter(recordable_or_type, recordable_id, column, delta)` | recordable type, ID, counter column, integer delta | `true` or `false` | Safely updates `recordings_count` or `events_count` style counters. |
| `dup_strategy_for(recordable_or_type)` | instance, class, or class name | callable or symbol | Resolves the duplication strategy used by `revise`. |
| `duplicate_recordable(recordable)` | recordable instance | duplicated recordable or `nil` | Duplicates a snapshot using the configured strategy. |
| `enable_capability(capability, on:)` | capability name, recordable type | configuration side effect | Enables a named capability for one recordable type. |
| `RecordingStudio::Capabilities.include_for(name, **options, &block)` | capability name, option hash, optional included callback | includable module | Builds the mixin hosts include via `.to`. Calls `enable_capability` and `set_capability_options` on include. Does not register the capability. |
| `capability_enabled?(capability, for:)` | capability name, recordable type | `true` or `false` | Checks whether an addon capability is enabled. |
| `capabilities_for(recordable_or_type)` | instance, class, or class name | sorted `Array<Symbol>` | Lists enabled capabilities for a type. |
| `set_capability_options(capability, on:, **options)` | capability name, recordable type, option hash | configuration side effect | Stores per-type capability options. |
| `capability_options(capability, for: type)` | capability name, recordable type | `Hash` or `nil` | Reads per-type capability options. |
| `record!(action:, recordable:, recording: nil, root_recording: nil, actor: nil, impersonator: nil, metadata: {}, occurred_at: Time.current, idempotency_key: nil, parent_recording: nil)` | write parameters | `RecordingStudio::Event` | Canonical low-level write API used by higher-level helpers. |
| `record_events!(entries)` | array of event entries | `Array<RecordingStudio::Event>` | Appends one event per entry to existing recordings in a single INSERT. |
| `lock_for_move!(recording, to_parent:, to_root:)` | recording, target parent, target root | frozen `Hash` | Locks a parent or root change in a stable order. See below. |

Capability-owned child recordables are for addon internals whose valid parents are determined by host recordables opting
into a capability:

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

The recording methods module may be omitted when a capability only contributes metadata. `source:` is required whenever
`child_recordables:` is present. It is provenance metadata, not an authentication boundary. Write paths only honor
capability-derived parents when both parent and child are registered recordable types and the child has a valid non-root
declaration.

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
- New recordings under an existing root need a `parent_recording:`; use `root_recording_for(recordable)` to create
  top-level roots.
- New child recordings enforce `recording_studio_recordable` parent rules before the recordable is saved.
- When `recording:` is present, the current recordable may be replaced, but its type cannot change.
- On success, the return value is always the new or reused `RecordingStudio::Event`.
- If `idempotency_key:` matches an existing event for the same recording, behavior depends on
  `config.idempotency_mode`.
- When `event_notifications_enabled` is true, a newly created event emits `recordings.event_created`.
  The payload includes `metadata`, a frozen copy of the event metadata with string keys (`{}` when nil).
  Existing payload keys stay as they are. See the Instrumentation section in the README.
- A create locks `parent_recording` with `FOR SHARE` and loads `root_recording` with no row lock.
  `FOR SHARE` keeps the parent's root stable until the insert commits, and it does not block
  another create. An update locks `recording` with `FOR UPDATE` and does not lock the root.
- The event insert, idempotency handling, and `before_record` / `after_record` hooks stay inside
  that same transaction.

### `RecordingStudio.record_events!(entries)`

Use this to append many events to recordings that already exist. The return value is an Array of
`RecordingStudio::Event` in input order.

Each entry is a Hash:

| Key | Required | Meaning |
| --- | --- | --- |
| `action` | yes | Event action string. |
| `recording` | yes | Persisted recording that receives the event. |
| `recordable` | yes | Must be `recording.recordable`. |
| `actor` | no | Falls back to the configured actor lambda, then `assert_actor!`. |
| `impersonator` | no | Falls back to the configured impersonator lambda. `nil` uses that fallback. |
| `metadata` | no | Normalized the same way as `record!`. Defaults to `{}`. |
| `occurred_at` | no | Stored as given. `nil` becomes a batch timestamp that increases by one microsecond per row. |

Behavior summary:

- No new recording is created, and the recording's recordable does not change.
- Recordings are locked with `Recording.lock_ids!` (`FOR UPDATE`, id order). The root is read with no row lock.
- `authorize_write!` runs for every row, then `before_record`, and only then does the INSERT run.
  `root_recording_id` is set on every row. `previous_recordable` is the current recordable.
- Every event is built and validated in Ruby first. An invalid row, an authorization denial, or a
  `recordable` that is not the recording's current recordable raises and inserts nothing.
- After the insert, each event is instrumented and then passed to `after_record`, in input order.
  `instrument_event` stays private.
- `events_count` is updated once per recordable after the outermost transaction commits.
- The call joins the caller's transaction, or opens one when none is open.
- `idempotency_key` raises. Batch dedupe is not part of this version.
- A given `occurred_at` is kept. Omitted times share one base `Time.current` and stay strictly increasing
  inside the batch, so the default timeline matches input order.

### `RecordingStudio.lock_for_move!(recording, to_parent:, to_root:)`

Call this inside an open transaction before changing `parent_recording_id` or `root_recording_id`.
Moveable and other gems that move recordings use it. A plain `record` / `revise` / `log_event!`
does not.

Lock order:

1. The recording's current root and `to_root`, ascending id, `FOR UPDATE`.
2. The recording, `to_parent`, and the current descendants, ascending id, `FOR UPDATE`,
   skipping ids already locked in step 1.

The parent's root cannot change under a create, because the create holds `FOR SHARE` on that
parent and this helper holds `FOR UPDATE` on the moved recording, the target parent, and the
descendants. A create under that subtree waits until the move commits, or it commits first and
is included in `descendant_ids`. A new id that would lock out of order raises `MoveConflict`
instead, and the retry includes it.

Return value, frozen:

| Key | Meaning |
| --- | --- |
| `recording` | Reloaded recording to `update!`. |
| `to_parent` | Reloaded target parent. |
| `to_root` | Reloaded target root. |
| `source_root` | Reloaded current root. |
| `descendant_ids` | Descendant ids to `update_all` with the new `root_recording_id`. Does not include `recording`. |

`update_all` those ids, then `update!` the returned recording with the new parent and root.
The save rewrites event `root_recording_id` values for the subtree. `update_all` does not.
Do not query descendants again after `update_all`; that query still filters on the old root.

`RecordingStudio::MoveConflict` means a new row appeared out of lock order, or a root changed
before its row was locked. Roll back the whole transaction and retry. Rescuing inside the
transaction keeps the old locks.

`ArgumentError` means the call is outside a transaction, a recording is not persisted, or
`to_parent` does not belong to `to_root`.

## Recordable Declarations

Every configured ActiveRecord recordable type should call the model macro:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true
end

class MessagesRoot < ApplicationRecord
  recording_studio_recordable label: "Messages", root: true, shared: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end
```

Macro parameters:

| Parameter | Required | Meaning |
| --- | --- | --- |
| `label:` | yes | Singular human-facing type label. Used by `recordable_type_label`. |
| `plural_label:` | no | Plural human-facing type label. Defaults to `label.pluralize`. |
| `root:` | yes | `true` when the type can be a root recording; `false` for child-only types. |
| `shared:` | no | `true` when a root type is a shared domain forest rather than an owned bucket. Defaults to `false`. Only valid with `root: true`, and cannot be combined with a non-empty `allowed_parent_types`. |
| `allowed_parent_types:` | required when `root: false` unless parent allowances are derived from a registered capability | Class names/classes allowed as direct parents. `[]` is valid but means the type cannot currently be nested anywhere unless capability enablement grants parents. |

Declaration behavior:

- `config.require_recordable_declarations` defaults to `true`; missing declarations raise
  `RecordingStudio::MissingRecordableDeclaration`.
- Setting `config.require_recordable_declarations = false` keeps legacy apps running while logging missing-declaration
  warnings. Invalid declarations still raise.
- A declaration for an unregistered type warns when declarations are not required and raises
  `RecordingStudio::InvalidRecordableDeclaration` when they are required.
- `allowed_parent_types` entries must be registered recordable types.
- Non-root capability-owned child recordables may omit `allowed_parent_types` only when a registered capability declares
  them in `child_recordables:`; effective parents are then derived from recordable types where that capability is enabled.
- Direct model saves validate hierarchy rules too, so bypassing `record!` does not create valid orphan recordings.
- Destroying a parent with children is restricted by the `child_recordings` association.
- Shared roots remain valid `root_recording_for` targets. Domain children may declare them as parents.
- Capability-derived parent allowances ignore shared root types, so capability-owned children cannot attach directly
  under a shared root. Enable those capabilities on descendants instead.

Hierarchy errors:

| Error | Raised when |
| --- | --- |
| `RecordingStudio::RootNotAllowed` | A non-root recordable is used where a root is required. |
| `RecordingStudio::InvalidParent` | A child is recorded without a parent or under a disallowed parent type. |
| `RecordingStudio::OrphanRecording` | A low-level new recording is attempted under an existing root without a parent. |
| `RecordingStudio::MissingRecordableDeclaration` | A configured ActiveRecord type has no declaration while declarations are required. |
| `RecordingStudio::InvalidRecordableDeclaration` | A declaration has invalid arguments, references unregistered parents, uses `shared:` incorrectly, or belongs to an unregistered type while strict declarations are enabled. |
| `RecordingStudio::TreeWalkError` | An ancestor or descendant walk repeats a recording or passes a depth of 1000. |
| `RecordingStudio::AuthorizationError` | `record!` or `record_events!` has no `config.authorize_write` (unless `allow_unauthorized_writes` is true), or the authorizer returned a falsey value. A denial in a batch inserts nothing. |
| `RecordingStudio::ActorRequired` | `record!` or `record_events!` has no actor (unless `allow_unauthorized_writes` is true and `require_actor` is false). |

## Configuration: `RecordingStudio::Configuration`

Use `RecordingStudio.configure` to access these settings.

| Setting or method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recordable_types` | nothing | `Array<String>` | Lists delegated recordable types currently registered. |
| `recordable_types=(types)` | array of classes or names | normalized array | Declares which recordable classes the engine should treat as delegated types. |
| `require_recordable_declarations` / `require_recordable_declarations=` | boolean | boolean | Requires configured ActiveRecord recordable types to declare hierarchy rules. Defaults to `true`. |
| `actor` | callable | callable | Supplies the default actor for writes when callers omit `actor:`. Writes with no actor raise `RecordingStudio::ActorRequired` unless `allow_unauthorized_writes` is true and `require_actor` is false. |
| `impersonator` | callable | callable | Supplies the default impersonator for writes when callers omit `impersonator:`. |
| `authorize_write` / `authorize_write=` | callable or `nil` | callable or `nil` | Host write gate invoked inside `record!`. Return truthy to allow. `nil` raises `RecordingStudio::AuthorizationError` unless `allow_unauthorized_writes` is true. |
| `allow_unauthorized_writes` / `allow_unauthorized_writes=` | boolean | boolean | Opt out of fail-closed writes. Default `false`. Set `true` only to keep the old open writes when no authorizer or actor is configured. |
| `require_actor` / `require_actor=` | boolean | boolean | When true, writes without an actor raise `RecordingStudio::ActorRequired`. Still applies when `allow_unauthorized_writes` is true. Redundant with the fail-closed default. |
| `event_notifications_enabled` | boolean | boolean | Enables ActiveSupport event instrumentation. |
| `idempotency_mode` | `:return_existing` or `:raise` | symbol | Controls duplicate idempotency-key behavior. |
| `recordable_dup_strategy` | symbol or callable | symbol or callable | Global fallback duplication strategy used by `revise`. |
| `recordable_dup_strategies` | nothing | `Hash<String, callable>` | Introspection for per-type duplication overrides. |
| `hooks` | nothing | `RecordingStudio::Hooks` | Global hook registry for extension points. |
| `gate_overrides` / `gate_overrides=` | hash or `nil` | frozen hash | Host `priority` and `enabled` flags for named gate checks. `nil` clears the map. Default `{}`. Unknown check names are kept and ignored when the gate runs. |
| `enable_capability(capability, on:)` | capability name, recordable type | internal set mutation | Enables a capability for one type. |
| `capability_enabled?(capability, for_type:)` | capability name, recordable type | `true` or `false` | Reads type-specific capability enablement. |
| `capabilities_for(recordable_or_type)` | instance, class, or class name | sorted `Array<Symbol>` | Returns enabled capabilities for a type. |
| `set_capability_options(capability, on:, **options)` | capability name, recordable type, options | stored options hash | Stores per-type addon options. |
| `capability_options(capability, for_type:)` | capability name, recordable type | `Hash` or `nil` | Reads per-type addon options. |
| `to_h` | nothing | serializable hash | Produces a summary of current configuration state. |
| `register_recordable_dup_strategy(type, callable = nil, &block)` | type and callable | stored callable | Overrides duplication for one recordable type. |
| `recordable_dup_strategy_for(recordable_or_type)` | instance, class, or class name | callable or symbol | Resolves the effective duplication strategy for a type. |
| `merge!(hash)` | hash-like object | merged configuration | Applies compatible keys from a hash, ignoring removed ones with a warning. |
| `app_name` / `app_name=` | `String` | `String` | Application name used for `<title>` and `og:site_name` fallbacks in the default layout. Defaults to `"RecordingStudio"`. |
| `default_background_image` / `default_background_image=` | `String` | `String` | Logical path or URL of the shared page backdrop. Defaults to `RecordingStudio::DEFAULT_BACKGROUND_IMAGE` (`"recording_studio/default_background.svg"`). `merge!` accepts the same key from `config/recording_studio.yml` and `config.x.recording_studio`. |
| `layout` / `layout=` | `nil`, `false`, layout name `String`, or a callable | the stored value | Host layout used when a gem's `recording_studio_layout` block returns `nil`. A callable is invoked as `call(controller:)`. `nil` means `RecordingStudio::DEFAULT_LAYOUT`. `false` means no layout. A blank string, a positional callable, or any other value raises `ArgumentError`. |
| `resolved_layout(controller:, default:)` | `controller:` keyword; optional `default:` | layout name or `false` | Resolves `configuration.layout` for one controller. `nil` (including a callable that returns `nil`) returns `default`, which defaults to `RecordingStudio::DEFAULT_LAYOUT`. `false` is returned as `false`. A positional call raises `ArgumentError`. |

Important behavior:

- `actor` defaults to `-> { Current.actor }` when `Current` exists.
- `impersonator` defaults to `-> { Current.impersonator }` when `Current` exists.
- Writes fail closed. Configure `authorize_write` and an actor. `allow_unauthorized_writes` defaults to `false`.
- `idempotency_mode = :return_existing` is retry-friendly and usually correct for HTTP or job retries.
- `recordable_dup_strategy = :dup` duplicates the recordable and clears known counter caches.
- `RecordingStudio::DEFAULT_LAYOUT` is `"recording_studio/default_layout"`. It is the layout when both the gem block and `configuration.layout` are `nil`.
- `RecordingStudio::DEFAULT_BACKGROUND_IMAGE` is `"recording_studio/default_background.svg"`. It is the starting value of `configuration.default_background_image`. The engine serves that file from `app/assets/images` and precompiles it when `config.assets.precompile` exists.
- Controllers call `recording_studio_layout { Gem.configuration.layout }`. The block is evaluated in the controller with no arguments. Lookup is that setting when it is not `nil`, then `configuration.layout`, then `RecordingStudio::DEFAULT_LAYOUT`. The macro defines `recording_studio_resolved_layout` and declares `layout :recording_studio_resolved_layout`, so subclasses inherit it. It also adds `helper RecordingStudio::LayoutHelper`.
- A layout callable accepts `controller:` only and returns a String, `nil` (try the next level), or `false` (no layout). `layout "name"` or `layout false` on a subclass still wins.
- `RecordingStudio::Layout.hardcoded_layout_paths(root, ignore: [])` lists controllers that hard-code `layout "recording_studio/..."`. `rake recording_studio:check_layouts` fails when the host tree has one.

## Translation: `RecordingStudio.t`

Use `RecordingStudio.t(key, **options)` (alias
`RecordingStudio::Translation.t`) for gem-shipped `recording_studio.*` keys.
It looks up the active locale first, then the loaded `:en` translation via
`locale: :en` (host English overrides included), then the caller's `default:`,
then an eager-loaded, deep-frozen English table built from the gem's
`config/locales/en.yml` plus every path registered with
`RecordingStudio::Translation.register_shipped_english` (deep-merged,
de-duplicated by expanded path; reset on Rails code reload; registrations
persist across reload). Host overrides in the active locale win.
Non-gem keys pass through to `I18n.t`. `_html` keys escape unsafe
interpolation args then mark the result `html_safe`, like view `t`. A missing
`_html` key with a non-interpolating caller `default:` stays unsafe like view
`t`; an interpolating caller `default:` is stricter (args escaped, result
`html_safe`). Partial pluralization data in a non-English locale still raises
`I18n::InvalidPluralizationData` (the English fallback does not fill missing
plural keys). Prefer this over hand-copied English `default:` strings.

Addon engines register shipped English at **boot time only**, from an
initializer (typically `before: "recording_studio.load_shipped_english"`).
Do not call `register_shipped_english` during a request. Requires
RecordingStudio `>= 4.7`, or guard with
`respond_to?(:register_shipped_english)` when supporting older hosts.
Missing or malformed registered files are skipped; `nil`/blank paths raise
`ArgumentError`.

```ruby
initializer "recording_studio_example.register_shipped_english",
            before: "recording_studio.load_shipped_english" do
  next unless RecordingStudio::Translation.respond_to?(:register_shipped_english)

  RecordingStudio::Translation.register_shipped_english(
    root.join("config/locales/en.yml")
  )
end
```

## Labels: `RecordingStudio::Labels`

Use this module when an addon needs recordable naming without duplicating UI heuristics.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `register_formatter(type, name: nil, type_label: nil, title: nil, summary: nil)` | recordable type and one or more callables | formatter registry mutation | Lets addons override display metadata for a type. |
| `formatters` | nothing | hash of formatter maps | Introspection and testing support. |
| `empty_label` | nothing | `String` | Locale-aware empty marker (`recording_studio.core.labels.empty` via `RecordingStudio.t`; missing locales fall back to loaded `:en`). |
| `name_for(recordable)` | recordable instance | `String` | Preferred display name for the recordable. |
| `label_for(recordable)` | recordable instance | `String` | Compatibility alias for `name_for`. |
| `type_label_for(recordable_or_type)` | instance, class, or class name | `String` | Human-facing type label. |
| `type_plural_label_for(recordable_or_type)` | instance, class, or class name | `String` | Human-facing plural type label. |
| `title_for(recordable)` | recordable instance | `String` | Optional presentation title. |
| `summary_for(recordable)` | recordable instance | `String` or `nil` | Optional summary/body snippet. |

`EMPTY_LABEL` remains the English `"—"` constant for direct references. Blank
inputs on the label helpers call `empty_label` so the active locale wins.
Helpers return an unfrozen I18n string; compare with `empty_label`, not
object identity against the constant.

Resolution order for `name_for(recordable)`:

1. Registered `name` formatter
2. `recordable.recordable_name`
3. `recordable.recording_studio_label` compatibility alias
4. Heuristics: `title`, `name`, built-in comment snippet, class plus ID fallback
5. Explicit type label fallback

Resolution order for `type_label_for(recordable_or_type)`:

1. Registered `type_label` formatter
2. Declaration `label:`
3. Legacy model methods (`recordable_type_label`, then `recording_studio_type_label`)
4. ActiveModel human name
5. Humanized class name

`type_plural_label_for(recordable_or_type)` returns declaration `plural_label:` when present and otherwise pluralizes
the resolved type label.

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

`extend_model` for `:recording` and `:event`, and `extend_controller` for `:application`, run from the engine `to_prepare` hook. Each block is applied once per class object. A reloaded class is a new object, so the block runs again. A class that stayed loaded is left alone.

### Class API via `RecordingStudio::Hooks`

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `run(event_name, *args)` | event name and args | `Array` of results | Convenience proxy to the global hook registry. |
| `run_around(event_name, context, &block)` | event name, context, block | block result | Convenience proxy for around hooks. |
| `trigger(event_name, *args)` | event name and args | `Array` of results | Alias-style convenience method for custom events. |

## Gates: `RecordingStudio.check_gate`

Gates are named allow and deny checks. They are not hooks, and they are not `config.authorize_write`.
Hooks run for side effects and swallow errors. `authorize_write` guards `record!`. A gate returns a
`RecordingStudio::GateDecision`. Core does not redirect, and it does not contain access or billing policy.

A gate name is a non-empty string or a symbol. Symbols are converted with `to_s` and surrounding space is
removed. A blank name raises `ArgumentError`. Check names use the same rule.

The conventional gate name is `<gem>.<gate>`, matching `/\A[a-z0-9_]+(\.[a-z0-9_]+)+\z/`.
`downloadable.stats` and `recording_studio.core.export` match. `stats` and `Host.Gate` do not.
A name outside that pattern warns once and is still accepted. The check runs.

### `RecordingStudio::GateDecision`

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `allow` | nothing | frozen decision | An allow. `gate` and `check` are `nil`. |
| `deny(redirect_to: nil, reason: nil, gate: nil, check: nil)` | optional redirect, reason, gate, and check | frozen decision | A deny. `check_gate` fills `gate` and `check` with the check that produced it. |
| `allowed?` | nothing | `true` or `false` | The check passed. |
| `denied?` | nothing | `true` or `false` | The check did not pass. |
| `redirect_to` | nothing | stored redirect or `nil` | Where the caller may send the actor. Core never redirects. |
| `reason` | nothing | stored reason or `nil` | Why the check denied. |
| `gate` | nothing | gate name or `nil` | Which gate produced a deny. `nil` on allow. |
| `check` | nothing | check name or `nil` | Which check produced a deny. `nil` on allow. |

String `redirect_to` and `reason` values are frozen copies. Two decisions with the same fields are equal.

### Registration

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `RecordingStudio.register_gate(gate_name, check_name, callable = nil, priority: 100, &block)` | names, callable or block, priority | normalized check name | Stores one check. A block and a callable at the same time use the callable. |
| `RecordingStudio.unregister_gate(gate_name, check_name)` | names | `true` or `false` | Removes one check. Missing names return `false`. |
| `RecordingStudio.gate_registered?(gate_name)` | gate name | `true` or `false` | True when at least one check is stored, even if every check is disabled. |
| `RecordingStudio.gate_checks(gate_name)` | gate name | array of frozen hashes | Debug list in run order. Each hash has `name`, `priority`, and `enabled`. Disabled checks stay in the list. |
| `RecordingStudio::Gates.reset!` | nothing | cleared registry and overrides | Drops every check and sets `config.gate_overrides` back to `{}`. Tests use this one call between examples. |

The registry is guarded by a mutex. Checks run after the snapshot is taken, so a check may register another gate without deadlocking.
Lower `priority` runs first. The default is `100`. Equal priorities keep registration order. Replacing a check updates its callable and priority, keeps its place in that order, and logs a warning.

`RecordingStudio::Gates.reset!` is the reload clear. Registering the same gate and check again replaces that one check, so an initializer that runs twice does not add a second copy.

### `RecordingStudio.check_gate`

```ruby
RecordingStudio.check_gate("downloadable.stats", actor: actor, recording: recording, plan: "pro")
```

`actor:` is required and may be `nil`. `recording:` defaults to `nil`. Other keywords are passed through to each check.

Each check is called as `call(actor:, recording:, **context)`. A block can ignore those keywords. A lambda must accept them. A lambda that accepts nothing raises, and that raise denies.

The result is `GateDecision.allow` when no checks are registered, or when every enabled check allows. An allow from a check does not stop later checks. `gate` and `check` on that allow are `nil`.

The first deny stops the run. `false` denies with no redirect and no reason. `GateDecision.deny` keeps that decision's `redirect_to` and `reason`, and `check_gate` sets `gate` and `check` to the check that returned it. Any other return value denies with no redirect and no reason. A raised error does the same. Both log a warning with the gate name and the check name. The original error does not propagate.

When `Rails.error` responds to `report`, that same failure is also reported:

```ruby
Rails.error.report(error, handled: true, context: { gate: gate_name, check: check_name })
```

An unexpected return is reported as an `ArgumentError` whose message names the class that came back. `handled: true` means the gate already turned the failure into a deny.

### Host overrides

```ruby
RecordingStudio.configure do |config|
  config.gate_overrides = {
    "downloadable.stats" => {
      "paywall" => { priority: 10 },
      "legacy" => { enabled: false }
    }
  }
end
```

`priority` is an integer. `enabled` is `true` or `false`. Any other setting raises `ArgumentError`. The assignment replaces the whole map. `nil` stores `{}`. `merge!` accepts the same key, including string keys from `config/recording_studio.yml`.

An override for a check that is not registered is ignored. When a logger is present the ignore is logged at debug. Otherwise it is a warning. It is not an error. A disabled check is not called. If every check is disabled, `check_gate` allows. Removing the override restores the priority stored at registration.

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
| `shared_root?` | nothing | `true` or `false` | Checks whether this recording is a shared root node. |
| `shared_root_tree?` | nothing | `true` or `false` | Checks whether this recording's tree root is a shared root. |
| `parentless?` | nothing | `true` or `false` | Checks whether `parent_recording_id` is blank. |
| `orphan?` | nothing | `true` or `false` | Checks whether this recording is parentless but not a valid declared root. |
| `leaf?` | nothing | `true` or `false` | Checks whether this recording has no children. |
| `root_recording_or_self` | nothing | `RecordingStudio::Recording` | Returns the root recording boundary for this recording. |
| `ancestors` | nothing | `Array<RecordingStudio::Recording>` | Root-to-parent ancestry. The walk raises `TreeWalkError` on a cycle or a depth over 1000. |
| `self_and_ancestors` | nothing | `Array<RecordingStudio::Recording>` | Includes the current recording after its ancestors. |
| `descendants` | nothing | `Array<RecordingStudio::Recording>` | Returns the full descendant subtree in parent-before-child order. |
| `self_and_descendants` | nothing | `Array<RecordingStudio::Recording>` | Includes the current recording before descendants. |
| `depth` | nothing | `Integer` | Depth from the root recording. |
| `level` | nothing | `Integer` | Alias for `depth`. |
| `descendant_ids(include_self: false)` | include-self flag | `Array` of IDs | Descendant ids ordered by depth, then id. Raises `TreeWalkError` on a cycle or a walk deeper than 1000. |
| `subtree_recordings(include_self: true, order: nil, scope: nil)` | include-self flag, optional order, optional scope | `ActiveRecord::Relation<RecordingStudio::Recording>` | Subtree relation ordered by depth, then id. A limit reads level by level and stops when the page is full. Raises `TreeWalkError` when that page reaches a cycle or a depth over 1000. |

### Event helpers on a single recording

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `events(actions: nil, actor: nil, actor_type: nil, actor_id: nil, from: nil, to: nil, limit: nil, offset: nil)` | event filters | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads history for one recording. |
| `recordables(limit: nil, cursor: nil, all: false)` | page size, cursor, or full history | `Array<ActiveRecord::Base>` | Distinct snapshots from this recording's events, oldest first. Reads 50 events unless `limit:` is set. The array responds to `next_cursor`. Pass that as `cursor:` for the next newer page. `all: true` returns the full history and does not take `limit:` or `cursor:`. The current recordable is included. |
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
- `record` defaults `parent_recording:` to the root; the child type must allow the root type as a parent.
- `record` builds/yields the recordable and delegates saving to `RecordingStudio.record!`.
- `revise` duplicates the current recordable using the configured duplication strategy.
- `revert` expects `to_recordable:` to be a compatible snapshot of the same recordable type.
- `log_event` and `log_event!` return the event, not the recording.

### Root-scoped query helpers

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recordings_query(include_children: false, type: nil, id: nil, parent_id: nil, created_after: nil, created_before: nil, updated_after: nil, updated_before: nil, order: nil, recordable_order: nil, recordable_filters: nil, recordable_scope: nil, limit: nil, offset: nil)` | recording and recordable filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Main read API for recordings under a root. Preloads the polymorphic recordable so list labels do not query once per row. |
| `recordings_of(recordable_class)` | class or class name | `ActiveRecord::Relation<RecordingStudio::Recording>` | Shortcut for `recordings_query(type: ...)`. |
| `recording_for(recordable)` | persisted recordable | `RecordingStudio::Recording` or `nil` | Finds one recording wrapper for a recordable in this root. |
| `recordings_for(recordables)` | array of persisted recordables | `Array<RecordingStudio::Recording>` | Batch version of `recording_for`, preserving input order. |
| `recordables_of(recordable_class, **options)` | recordable class plus query options | `Array<ActiveRecord::Base>` | Returns recordables instead of recording wrappers. |
| `child_recordings_of(parent_recording, **options)` | parent recording plus query options | `ActiveRecord::Relation<RecordingStudio::Recording>` | Reads direct children under the same root. |
| `events_query(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, limit: nil, cursor: nil)` | root recording filters plus event filters | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads an event timeline for a root or a filtered slice. A root-wide read defaults to 50 rows and pages with `cursor:`. |
| `recordings_with_events(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, actions: nil, actor: nil, actor_type: nil, actor_id: nil, impersonator: nil, impersonator_type: nil, impersonator_id: nil, from: nil, to: nil, order: nil, limit: nil, offset: nil)` | root recording filters plus event filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Finds recordings whose history matches event filters. |
| `recordings_with_children(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, child_type: nil, child_id: nil, child_recording_id: nil, child_recordable_filters: nil, child_recordable_scope: nil, order: nil, limit: nil, offset: nil)` | parent and child filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Finds recordings that have matching direct children. |
| `recordings_with_descendants(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, descendant_type: nil, descendant_id: nil, descendant_recording_id: nil, descendant_recordable_filters: nil, descendant_recordable_scope: nil, order: nil, limit: nil, offset: nil)` | parent and descendant filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Recordings with matching descendants below them. A limit with no descendant filter returns recordings that have a child, ordered by id. A descendant filter still walks ancestors and raises `TreeWalkError` on a cycle or a depth over 1000. |
| `recordings_without_children(include_children: true, type: nil, id: nil, recording_id: nil, parent_id: nil, recordable_filters: nil, recordable_scope: nil, child_type: nil, child_id: nil, child_recording_id: nil, child_recordable_filters: nil, child_recordable_scope: nil, order: nil, limit: nil, offset: nil)` | parent and child filters | `ActiveRecord::Relation<RecordingStudio::Recording>` | Finds recordings that do not have matching direct children. |

Query guidance:

- `include_children: false` means direct children of the root only.
- `include_children: true` means the full root tree.
- `type:` should be a class or class name. It scopes both recording wrappers and recordable joins.
- `id:` filters by `recordable_id`, not by `recording.id`.
- `recording_id:` exists on `events_query` and `recordings_with_events` when you need to target one recording wrapper.
- `recordable_filters:` accepts a `Hash`, `ActiveRecord::Relation`, or Arel node.
- `recordable_scope:` must be trusted code. It receives a relation and may return a relation.
- Child and descendant query helpers support the same filter/scope pattern with `child_recordable_filters`,
  `child_recordable_scope`, `descendant_recordable_filters`, and `descendant_recordable_scope`.
- `order:` is sanitized against recording columns.
- `recordable_order:` is sanitized against recordable columns for the resolved `type:`.
- A root-wide `events_query` (no type, recording, parent, or recordable filter, `include_children: true`) reads `events.root_recording_id`. It does not join recordings, does not take `offset:`, and does not count the timeline.
- That root-wide read returns `RecordingStudio::Event::ROOT_TIMELINE_LIMIT` (50) rows unless you pass `limit:`.
- Order is `occurred_at DESC`, `created_at DESC`, `id DESC`.
- `RecordingStudio::Event.cursor_for(event)` returns an opaque cursor. Pass it as `events_query(cursor:)` to read the next older page.
- A short page, or an empty page after a full one, means the timeline is finished.
- Filtered `events_query` calls still select through recordings and apply a limit only when you pass `limit:`.
- `RecordingStudio::Event.for_root` is the same root filter without a default limit. Pass `limit:` when you want a page.

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
| `for_root(root_recording_or_id)` | root recording or ID | `ActiveRecord::Relation<RecordingStudio::Event>` | Reads events whose `root_recording_id` is that root. Does not join recordings and does not limit. |
| `cursor_for(event)` | event | `String` | Opaque cursor for the next older `events_query` page. |
| `timeline` | nothing | `ActiveRecord::Relation<RecordingStudio::Event>` | Orders by `occurred_at`, `created_at`, then `id`, newest first. |
| `older_than_cursor(cursor)` | cursor string | `ActiveRecord::Relation<RecordingStudio::Event>` | Keyset filter for rows older than the cursor. A blank cursor is a no-op. An invalid cursor raises `ArgumentError`. |
| `newer_than_cursor(cursor)` | cursor string | `ActiveRecord::Relation<RecordingStudio::Event>` | Keyset filter for rows newer than the cursor. Used by `recording.recordables`. A blank cursor is a no-op. An invalid cursor raises `ArgumentError`. |
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
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end

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

timeline = root.events_query
next_cursor = RecordingStudio::Event.cursor_for(timeline.last) if timeline.size == timeline.limit_value
older = root.events_query(cursor: next_cursor)
```

## Layout Helpers: `RecordingStudio::LayoutHelper`

Available in views when the controller calls `recording_studio_layout` (the
macro adds the helper) or manually adds `helper RecordingStudio::LayoutHelper`.

Public layout:

- `recording_studio/default_layout` — page shell (see `docs/layouts/default_layout.md`)

### Head and SEO

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `default_layout_head(&block)` | block | `nil` | Adds block content to `<head>` via `yield :head`. |
| `recording_studio_seo_description(text)` | description string | `nil` | Sets `<meta name="description">` and `og:description`. |

### Background

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recording_studio_default_background_image` | nothing | `String` or `nil` | Returns `configuration.default_background_image`, stripped. Falls back to `RecordingStudio::DEFAULT_BACKGROUND_IMAGE` when the configuration object has no such reader. Blank becomes `nil`. |
| `recording_studio_background_image(url = :default)` | no argument, `true`, `:default`, a path `String`, `nil`, or `false` | `nil` | No argument, `true`, and `:default` store the shared image. A non-blank string stores that path. `nil`, `false`, and a blank string store nothing. |
| `content_for :background_image, url` | image URL, `"true"`, `"default"`, or `"false"` |  | Same slot, without the helper. The layout treats `"true"` and `"default"` as the shared image and `"false"` as no image. |

### Page width

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `recording_studio_page_width(width)` | `:narrow`, `:default`, `:wide`, or `:full` | `nil` | Sets `content_for :page_width`. The default layout passes it to `FlatPack::PageLayout`. |
| `content_for :page_width, width` | the same names |  | Same slot, without the helper. A blank value stays `:default`. |

### Page nav

Flatpack owns the back row and the button group. Recording Studio adds custom left and right slots. Call these from the view. The layout renders them.

| Method | Takes | Returns | Why it exists |
| --- | --- | --- | --- |
| `content_for :title` / `:subtitle` | string |  | Document title and `FlatPack::PageTitle`. |
| `flat_pack_page_nav` | `round: true`, `style: :default`, `back_href`, `back_tooltip`, `anchor_href`, `anchor_tooltip` | `nil` | Stores the back and close row. |
| `register_page_nav` | label, path, `role:`, optional `icon:`, `overflow:` | `nil` | Records one page action. `role` is `:primary`, `:secondary`, or `:destructive`. |
| `recording_studio_page_nav_left(&block)` | block | `nil` | Writes the block to `content_for :page_nav_left`. |
| `recording_studio_page_nav_right(&block)` | block | `nil` | Writes the block to `content_for :page_nav_right`. |

The layout is `FlatPack::PageLayout`. `width` comes from `:page_width` and defaults to `:default`. `top_nav_width`
and `content_scroll` stay at their defaults (`:content` and `:below`). When
`content_for(:background_image)` is present, the layout fills
`layout.background` with one decorative `image_tag` (`alt=""`, `loading="lazy"`).
Flatpack paints that image as the page backdrop. A blank slot skips it.
`"false"` skips it. `"true"` and `"default"` use
`recording_studio_default_background_image`. Any other non-blank string is
the image path.
The layout calls `flat_pack_page_nav_tag` and one `page_nav_button_group`
(`variant: :outlined`, ghost `sm` for every role, `collapse: :menu`) inside
`FlatPack::TopNav::Component.new(padding: :none, size: :lg)`. It also reads
`content_for(:page_nav_left)` and `content_for(:page_nav_right)`. Left custom
HTML renders first and the back row second, as siblings in TopNav's left
section (`flex items-center gap-2`). Right custom HTML renders first and the
button group second, as siblings in TopNav's right section
(`flex items-center justify-end gap-2`).
The back row, `:page_nav_left`, the button group, or `:page_nav_right` each
draw the top nav.
Pass `round: true, style: :default` to `flat_pack_page_nav` so back and close are
round buttons with `data-fp-style="default"`. `<html>` is `data-theme="rounded"`.

### Example

```erb
<% content_for :title, "Workspaces" %>
<% content_for :subtitle, "Pick one to open." %>
<% flat_pack_page_nav(round: true, style: :default, anchor_href: root_path, anchor_tooltip: "Home") %>
<% recording_studio_seo_description("Browse and manage your workspaces") %>
<% recording_studio_background_image %>
<% recording_studio_background_image("/photos/cover.png") %>
<% recording_studio_page_width(:wide) %>
<% register_page_nav "New workspace", new_workspace_path, role: :primary, icon: :plus %>
<% recording_studio_page_nav_left do %>
  <%= render FlatPack::Button::Component.new(text: "Studio", style: :ghost, size: :sm, href: root_path) %>
<% end %>
<% recording_studio_page_nav_right do %>
  <%= render FlatPack::Button::Component.new(text: "New note", icon: "plus", icon_only: true, round: true, size: :sm, href: new_note_path) %>
<% end %>
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