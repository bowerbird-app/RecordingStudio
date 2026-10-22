# Upgrade Guide

## Unreleased

`recordings.event_created` payloads include `metadata`, the hash stored on the event (`{}` when the
write stored none). Existing keys, `schema_version`, and actor and impersonator semantics are
unchanged. No host change is required. Read `payload[:metadata]` for fields a caller stored there,
such as `authorized_by_type` and `authorized_by_id`.

## Upgrading To 5.0.0

This is a breaking upgrade. `RecordingStudio::UsesDefaultLayout` is removed.
There is no compatibility shim.

### What Changed

- Controllers opt in with the class macro `recording_studio_layout`. The block
  returns that gem's layout setting and is evaluated in the controller with no
  arguments. The macro defines `recording_studio_resolved_layout`, declares
  `layout :recording_studio_resolved_layout`, and adds
  `helper RecordingStudio::LayoutHelper`. Subclasses inherit the declaration
  through Rails, including when a parent class already opted in.
- Lookup order: the block's setting when it is not `nil`, then
  `RecordingStudio.configuration.layout` when that is not `nil`, then
  `RecordingStudio::DEFAULT_LAYOUT` (`"recording_studio/default_layout"`).
- A setting may be a layout name, `false` (no layout), `nil` (try the next
  level), or a callable. Call the callable as `call(controller:)`. It returns
  a String, `nil`, or `false` with the same meaning. A positional parameter
  raises `ArgumentError`. A callable that returns `nil` now falls through; it
  no longer selects a nil layout.
- `layout "name"` or `layout false` on a gem or host subclass still wins.
- `RecordingStudio::ApplicationController` uses the same lookup. An unset
  `configuration.layout` selects `RecordingStudio::DEFAULT_LAYOUT`, not
  `"application"`.
- `recording_studio/action_layout` is removed, including its shared partial,
  the `page_nav` partial, and the dummy `/action_layout_demo` route. Show,
  new, and edit screens use the default layout. The view generator no longer
  emits TopNav slots.
- The default layout is one minimal page shell: back and anchor only. It no
  longer reads `:body_theme`, `:seo_image`, `:page_nav_back_icon`,
  `:page_nav_back_style`, `:page_nav_back_size`, or `:page_nav_anchor_icon`.
  `recording_studio_seo_image` is removed. Back stays `chevron-left` /
  secondary / md. The anchor stays `x-mark` and appears only when
  `page_nav_anchor_url` is set. `:title`, `:head`, `:seo_description`,
  back and anchor URL and label, `:page_nav_right`, Flatpack stylesheets,
  and flash alerts stay. See
  [docs/layouts/default_layout.md](layouts/default_layout.md#host-layout-contract).
- Give each gem surface its own setting (default `nil`) and its own base
  controller block. A host sets `RecordingStudio.configuration.layout` for
  every nil block, or sets one gem setting to override that surface.
- `flat_pack` (>= 0.1.275) is a required runtime dependency. The default
  layout renders `FlatPack::PageNav::Component` for back and anchor and no
  longer includes a Button, plain-link, or hand-built history-back fallback.
  `flat_pack` is not on RubyGems. Add the git source in the host Gemfile:

  ```ruby
  gem "flat_pack", git: "https://github.com/bowerbird-app/flatpack.git", tag: "v0.1.275"
  ```

### Upgrade Steps

On the gem's base controller, replace the concern and any hard-coded
`layout "recording_studio/default_layout"`:

```ruby
class ApplicationController < ActionController::Base
  recording_studio_layout { RecordingStudioX.configuration.layout }
end
```

Leave the block returning `nil` when the gem has no layout of its own. Core
`configuration.layout` and then `RecordingStudio::DEFAULT_LAYOUT` apply.

To force the host application layout for every controller that reaches core:

```ruby
RecordingStudio.configure do |config|
  config.layout = "application"
end
```

A controller that renders with no layout declares that itself:

```ruby
class PreviewsController < ApplicationController
  layout false
end
```

`RecordingStudio::Layout.hardcoded_layout_paths(root)` lists remaining
`layout "recording_studio/..."` calls. `rake recording_studio:check_layouts`
exits non-zero when the app tree still has one. Pass `ignore:` for a file
that should stay.

## Upgrading To 4.7.1

This is a patch upgrade. The default layout name is unchanged.

### What Changed

- The shared default layout renders `FlatPack::PageNav` with the ordered row
  API: `with_back`, `with_close`, and `with_item`. `page_nav_back_url` is the
  back control href. `page_nav_back_label` and `page_nav_anchor_label` are
  tooltips. The right-hand cluster is a `with_item` block pushed with
  `ml-auto`.
- Development and test depend on `flat_pack` tag v0.1.275. Page nav keywords
  removed in Flatpack 0.1.274 raise if a host still passes them. The dummy
  sign-in card uses style `:shaded` because `:elevated` is no longer a card
  style.
- `RecordingStudio.configuration.layout` lets a host set the layout used by
  core controllers. A String names the layout. A lambda or proc is called as
  `call(controller:)`. `nil` keeps the previous layout: `"application"` on
  `RecordingStudio::ApplicationController`, and
  `"recording_studio/default_layout"` when a controller includes
  `RecordingStudio::UsesDefaultLayout`.

### Upgrade Steps

No migration is required. Hosts that use the shared layouts as-is need no
change.

Hosts that override the core layout or the page nav partial must render
`FlatPack::PageNav` with the Flatpack >= 0.1.274 API. Do not pass `back_icon`,
`back_label`, `back_style`, `back_size`, `anchor_icon`, `anchor_label`,
`anchor_href`, or `right_slot` into `FlatPack::PageNav::Component`. Do not
pass raw `params` into `with_close`. A close href comes from
`page_nav_anchor_url`. When a screen needs the safe return URL, use
`flat_pack_return_to` or `FlatPack::ReturnTo.origin_url`.

To select a layout from the host, set `layout` in the Recording Studio
initializer:

```ruby
RecordingStudio.configure do |config|
  config.layout = "application"
end
```

```ruby
RecordingStudio.configure do |config|
  config.layout = ->(controller:) { "recording_studio/default_layout" }
end
```

## Upgrading To 4.7.0

This is a minor upgrade. Default English interface text is unchanged.

### What Changed

- Addon engines can register additional English locale files for the final
  shipped-English fallback via
  `RecordingStudio::Translation.register_shipped_english(path)`.
- Registration is boot-time only (engine initializer). Missing or malformed
  registered files are skipped; `nil`/blank paths raise `ArgumentError`.
- The fallback table deep-merges base `config/locales/en.yml` with every
  registered file (de-duplicated by expanded path). Registrations persist
  across Rails code reload; the table is rebuilt on `to_prepare`.
- Fallback order is unchanged: loaded `:en`, then caller `default:`, then the
  merged shipped table. Present keys remain byte-identical to `I18n.t`.

### Upgrade Steps

No migration is required for hosts.

Addon gems that ship `recording_studio.<gem>.*` keys need RecordingStudio
`>= 4.7` (or a `respond_to?(:register_shipped_english)` guard) and should
register their `config/locales/en.yml` from an engine initializer at boot so
English remains available when the loaded `:en` backend no longer has those
keys:

```ruby
initializer "recording_studio_example.register_shipped_english",
            before: "recording_studio.load_shipped_english" do
  next unless RecordingStudio::Translation.respond_to?(:register_shipped_english)

  RecordingStudio::Translation.register_shipped_english(
    root.join("config/locales/en.yml")
  )
end
```

## Upgrading To 4.6.0

This is a minor upgrade. Default English interface text is unchanged.
Gem-shipped `recording_studio.*` keys now fall back when the active locale has
no translation: loaded `:en` (host English overrides included), then the
caller's `default:`, then an eager-loaded, deep-frozen copy of the gem's own
`config/locales/en.yml` (reset on Rails code reload).

### What Changed

- New `RecordingStudio.t` / `RecordingStudio::Translation.t` helper looks up a
  key in the active locale and, when missing, uses the loaded `:en` value via
  `I18n.t(..., locale: :en)`, then the caller's `default:`, then the
  gem-shipped English table (eager-loaded and deep-frozen at boot; reset on
  Rails code reload). Non-gem keys and present locale values pass through like
  `I18n.t`. `_html` keys escape interpolation args like view `t`. A missing
  `_html` key with a non-interpolating caller `default:` stays unsafe like
  view `t`; an interpolating caller `default:` is stricter (args escaped,
  result `html_safe`).
- Default layout, shared page-nav, and `Labels.empty_label` call
  `RecordingStudio.t` instead of `t(...)` / `I18n.t(...)` with hand-copied
  English `default:` strings.
- `en.yml` is byte-identical to 4.5.0. No new keys.

### Upgrade Steps

No migration is required. English hosts need no change.

Hosts that set raise-on-missing translations will no longer raise for
gem-shipped keys resolved through `RecordingStudio.t` (including the layout /
Labels call sites) when loaded `:en` or the gem-shipped table has the key.
Host overrides in the active locale still win.

Partial pluralization in a non-English locale (for example French with only
`one` and a `count` of 5) still raises `I18n::InvalidPluralizationData`, the
same as bare `I18n.t` — the English fallback does not fill missing plural
keys.

To override or add another language, set the existing
`recording_studio.core.navigation.*` and `recording_studio.core.labels.empty`
keys in the host's `config/locales`.

## Upgrading To 4.5.0

This is a minor upgrade. Default English interface text is unchanged. Empty
label helpers now resolve through Rails I18n at call time.

### What Changed

- `RecordingStudio::Labels` empty markers use
  `recording_studio.core.labels.empty` via `Labels.empty_label` (and the
  existing blank-input paths on `name_for` / `label_for` / `type_label_for` /
  `type_plural_label_for` / `title_for`).
- The public constant `Labels::EMPTY_LABEL` remains the English `"—"` string
  for direct references; it is not locale-aware.
- Label helpers return an unfrozen I18n string (not the frozen `EMPTY_LABEL`
  constant object). Do not use `equal?` / `frozen?` against the constant;
  compare with `Labels.empty_label`.
- `Recording#name` / `Recording#label` detect the empty marker via
  `Labels.empty_label` so translated empty markers still fall back to the
  type label.
- Layout / page-nav `t(...)` calls pass English `default:` values so a host
  locale with no fallback never shows “translation missing”.
- `.release-please-manifest.json` matches `RecordingStudio::VERSION`.
- `RecordingStudio::Labels.label_for` works as a module function (previously
  the alias was instance-only after `module_function`).

Keys added:

| Key | English |
| --- | --- |
| `recording_studio.core.labels.empty` | — |

Left untranslated on purpose: developer `ArgumentError` / authorization /
capability exceptions, generator CLI text, log lines, AR validation messages
that name internal hierarchy fields (`parent_recording_id`, root recording),
config default `app_name` (`"RecordingStudio"`), the developer placeholder
`CHANGE_APP_NAME_IN_DEFAULT_LAYOUT`, icon/style tokens, and dynamic
recordable/user content.

### Upgrade Steps

No migration is required. English hosts need no change.

If you compared helper output to `RecordingStudio::Labels::EMPTY_LABEL`
(including `equal?` or `frozen?` checks), switch to `Labels.empty_label`.
That comparison stays correct when the active locale translates
`recording_studio.core.labels.empty`.

To override or add another language, set the key above (and the existing
`recording_studio.core.navigation.*` keys) in the host's `config/locales`.

## Upgrading To 4.4.0

This is a non-breaking upgrade. Rendered English interface text is unchanged.
Callers that pass their own PageNav labels via `content_for` keep working.

### What Changed

- Static layout/page-nav copy in the gem's own views uses Rails I18n keys under
  `recording_studio.core.navigation`.
- The gem ships English only in `config/locales/en.yml` (Rails engines load
  that path by default). There is no dependency on
  `recording_studio_internationalization`.

Keys added:

| Key | English |
| --- | --- |
| `recording_studio.core.navigation.back` | Back |
| `recording_studio.core.navigation.go_back` | Go back |
| `recording_studio.core.navigation.close` | Close |
| `recording_studio.core.navigation.page` | Page navigation |
| `recording_studio.core.navigation.action_page` | Action page navigation |

Left untranslated on purpose: the developer placeholder
`CHANGE_APP_NAME_IN_DEFAULT_LAYOUT`, icon/style tokens, flash/user content, and
caller-provided titles/labels.

### Upgrade Steps

No migration is required. English hosts need no change. To override or add
another language, set the keys above in the host's `config/locales`.

## Upgrading To 4.3.0

This is a non-breaking upgrade. Existing `UsesDefaultLayout` hosts keep the
same PageNav-rendered output.

### What Changed

- Public `recording_studio/default_layout` is a thin wrapper around
  `recording_studio/shared/_default_layout`. Markup and slots are unchanged.
- `rails g recording_studio:views RESOURCE` scaffolds FlatPack templates.

### Upgrade Steps

No migration is required for a 4.3.0 install. 5.0.0 removes the TopNav
layout this release added. Follow [Upgrading to 5.0.0](#upgrading-to-500).

## Upgrading To 4.2.1

This is a non-breaking upgrade. Recording, recordable, and host APIs are unchanged.

### What Changed

Cloud Agent Builds run `.cursor/install.sh`, then `.cursor/fetch-skills.sh`.
On a warm snapshot the install hook skips apt, ruby-build, db:prepare, and
tailwind when Ruby, bundle, and Postgres are already usable. A skippable
provision failure does not fail the Build. Fetch-skills always runs last.

The repository gitignores `.cursor/skills/` and `.cursor/rules/`. It does not
vendor `SKILL.md` or plugin `*.mdc` files. The gemspec still packages only
`app`, `config`, `db`, and `lib`, plus the license, Rakefile, and README.

See [Cursor skills in Cloud Agents](cursor-skills.md).

### Upgrade Steps

No migration is required.

Rebuild the Cloud Agent environment with Draft off so Build loads the pack.

## Upgrading To 4.2.0

This is a non-breaking upgrade. Existing `enable_capability` / `set_capability_options` call sites keep working.

### What Changed

- Core adds `RecordingStudio::Capabilities.include_for(:name, **options, &block)`.
- On include, the factory enables the named capability and stores options. It does not register the capability.
- The factory lives on `RecordingStudio::Capabilities`, not on the `RecordingStudio::Capability` concern mixed into `Recording`.
- Hosts enable a mixin with one verb: `include RecordingStudio::Capabilities::<Name>.to(**opts)`.
- Installing a mixin gem still does not enable it. Parent rules stay on `recording_studio_recordable`.

### Upgrade Steps

No migration is required.

Mixin authors can wrap the factory without moving option schemas into core:

```ruby
module RecordingStudio
  module Capabilities
    module Reviewable
      def self.to(**options)
        RecordingStudio::Capabilities.include_for(:reviewable, **options)
      end
    end
  end
end
```

Keep `register_capability` at boot, outside `.to` / `include_for`.

Hosts opt each recordable type in explicitly:

```ruby
class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace"]

  include RecordingStudio::Capabilities::Reviewable.to(approval_class: "Approval")
end
```

## Upgrading To 4.1.0

This is a non-breaking upgrade. Existing root types stay owned buckets unless you opt a type into `shared: true`.

### What Changed

- `recording_studio_recordable` accepts `shared:` (default `false`).
- `shared: true` is only valid with `root: true` and cannot be combined with a non-empty `allowed_parent_types`.
- Shared roots remain valid `root_recording_for` targets and write/query boundaries.
- Capability-owned children cannot use a shared root as a direct parent, even if that type is also listed in
  `allowed_parent_types:`. Domain children still can, by listing the shared root type in `allowed_parent_types:`.
- New helpers: `shared_root_type?`, `shared_root_types`, `shared_root_declarations`, `shared_root?`,
  `shared_root_tree?`, plus `recording.shared_root?` and `recording.shared_root_tree?`.

### Upgrade Steps

No migration is required. Existing declarations omit `shared:` and keep the previous meaning.

To add a shared domain forest such as messages:

```ruby
class MessagesRoot < ApplicationRecord
  recording_studio_recordable label: "Messages", root: true, shared: true
end

class MessageGroup < ApplicationRecord
  recording_studio_recordable label: "Message group",
                              root: false,
                              allowed_parent_types: ["MessagesRoot"]
end
```

Then:

1. Register the types in `config.recordable_types`.
2. Persist the Messages root recordable and call `RecordingStudio.root_recording_for`.
3. Enable Accessible (and other capability-owned children) on `MessageGroup`, not on `MessagesRoot`.
4. Keep the shared root out of Root Switchable and Billing; those addons should treat `shared_root_types` as
   non-switchable, non-billable buckets.

Access grants on the shared root itself remain an Accessible follow-up. Core already rejects capability-owned children
as direct children of a shared root, including `record!` bypasses.

Helpful checks:

```ruby
RecordingStudio.shared_root_types
RecordingStudio.shared_root?(messages_root)
RecordingStudio.parent_allowed?(child_type: "MessageGroup", parent_recording: messages_root)
```

## Upgrading To 4.0.0

This guide covers the breaking changes between `3.x` and `4.0.0`: integrity hardening, Event append-only history,
query safety defaults, and removal of Recording's implicit default order.

## Upgrade Impact

This is a breaking upgrade for:

- callers that relied on `RecordingStudio::Recording` returning newest-first without `.recent` or an explicit `order:`
- code that updated or destroyed `RecordingStudio::Event` rows through ActiveRecord
- query call sites that pass `recordable_scope:`, Relation/Arel `recordable_filters:`, or subtree `scope:` procs
- `revert` call sites that pointed a recording at a snapshot outside that recording's event history
- apps that depended on `RecordingStudio::Services::ExampleService`

## What Changed

- `Recording` no longer has a `default_scope` order. Prefer `Recording.recent` or pass `order:` to query helpers.
- Events are append-only at the ActiveRecord layer. Intentional retention purges must use SQL `delete_all` (recording
  destruction uses `dependent: :delete_all` for events).
- Relation/Arel/proc recordable query escape hatches require
  `config.allow_unsafe_recordable_queries = true` or per-call `allow_unsafe_recordable_query: true`.
- `revert` validates that `to_recordable` appears in the target recording's history.
- Unique root index prevents duplicate root recordings for the same recordable.
- New optional production controls: `require_actor`, `authorize_write`, and `max_metadata_bytes`.
- `RecordingStudio.record!` fires `before_record` / `after_record` hooks.
- Template `ExampleService` was removed; keep using `Services::BaseService` for host/addon commands.

## Upgrade Steps

1. Install and run the harden migration.

```bash
rails g recording_studio:migrations
rails db:migrate
```

If you already installed from the fresh-install set, the generator should copy
`harden_recording_studio_indexes_and_constraints`. Resolve any duplicate root recordings before migrating if the unique
index cannot be created.

2. Replace implicit recording ordering.

```ruby
# before
RecordingStudio::Recording.where(root_recording_id: root.id).first

# after
RecordingStudio::Recording.recent.where(root_recording_id: root.id).first
# or
root.recordings_query(order: { updated_at: :desc }).first
```

3. Opt in where trusted code needs unsafe query escape hatches.

```ruby
RecordingStudio.configure do |config|
  config.allow_unsafe_recordable_queries = true # host-wide trusted mode
end

root.recordings_query(
  type: Page,
  recordable_scope: ->(scope) { scope.where(pages: { published: true }) },
  allow_unsafe_recordable_query: true # per-call opt-in
)
```

Hash `recordable_filters:` remain column-whitelisted and do not need the flag.

4. Ensure revert targets come from history.

```ruby
original = page_recording.recordable
root.revise(page_recording) { |page| page.title = "Updated" }
root.revert(page_recording, to_recordable: original) # ok: original is in history
```

5. Recommended production write hardening.

```ruby
RecordingStudio.configure do |config|
  config.require_actor = true
  config.authorize_write = lambda { |root_recording:, actor:, **|
    actor.present? && Current.user&.can_write?(root_recording)
  }
  config.max_metadata_bytes = 16_384
end
```

6. Replace any `ExampleService` usage with your own `BaseService` subclass.

## Compatibility Notes

- Idempotency keys and `root_recording_for` are race-safer under concurrency via unique indexes plus `RecordNotUnique`
  rescue.
- Counter caches may not decrement when events are purged with `delete_all`; recompute or adjust counters in retention
  jobs when needed.

---

# Upgrading To 3.0.0

This guide covers the breaking changes between `2.0.0` and `3.0.0`: declaration-enforced recordable hierarchies and
capability-owned child recordables.

## Upgrade Impact

This is a breaking upgrade for:

- host apps with configured ActiveRecord recordable types that do not declare `recording_studio_recordable(...)`
- apps that previously treated child-only recordables as roots
- addons that own internal child recordables but do not register them through
  `RecordingStudio.register_capability(..., source:, child_recordables:)`

## What Changed

- Every configured ActiveRecord recordable type is expected to call `recording_studio_recordable(...)`.
- Declarations now define the type label, optional plural label, root eligibility, and declared parent types.
- `config.require_recordable_declarations` defaults to `true`; missing declarations raise
  `RecordingStudio::MissingRecordableDeclaration`.
- Capability-owned child recordables fail closed when undeclared, even if
  `config.require_recordable_declarations = false`.
- Non-root recordables must declare `allowed_parent_types:` unless their parent allowance is derived from an enabled
  capability.
- `RecordingStudio.root_recording_for(recordable)` only accepts recordables declared with `root: true`.
- New child recordings must have an allowed `parent_recording`; invalid parent/child combinations raise
  `RecordingStudio::InvalidParent` before the recordable is saved.
- Direct `RecordingStudio::Recording` saves also validate declaration rules, so bypassing `record!` does not create valid
  orphan recordings.
- Parent recordings with children are restricted from destruction by the `child_recordings` association.
- Type labels now prefer declaration `label:` and `plural_label:` before legacy label methods.

## Upgrade Steps

1. List every configured recordable type and any addon-owned child recordables.

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace", "Page", "Comment"]
end
```

Inventory any addon-owned child recordables that should no longer be expressed as host-app-specific
`allowed_parent_types:` declarations.

2. Add `recording_studio_recordable` to every configured ActiveRecord model.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end

class Comment < ApplicationRecord
  recording_studio_recordable label: "Comment", root: false, allowed_parent_types: ["Page"]
end
```

Keep `allowed_parent_types:` on domain recordables. Only omit it for addon-owned child recordables whose parents are
derived from capability enablement.

3. Keep root creation and child creation separate.

```ruby
workspace = Workspace.find_or_create_by!(name: "Studio")
root_recording = RecordingStudio.root_recording_for(workspace)

page_recording = root_recording.record(Page) do |page|
  page.title = "Getting started"
end

comment_recording = root_recording.record(Comment, parent_recording: page_recording) do |comment|
  comment.body = "Looks good"
end
```

Use `root_recording_for` only for declared roots. Use `root_recording.record(..., parent_recording: ...)` for child
recordables whose declarations use `root: false`.

4. If you ship addon-owned child recordables, register them with their capability.

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Host recordables should enable capabilities through mixins:

```ruby
class Page < ApplicationRecord
  include RecordingStudioAccessible::Accessible
end
```

The mixin should call `RecordingStudio.enable_capability(:accessible, on: name)`. Core then derives the effective parent
allowance for `RecordingStudio::Access` under `Page`. Capability-owned child recordables must be registered, declared,
and non-root. `source:` is required when `child_recordables:` is present and is provenance metadata, not an authentication
boundary.

5. If you need a staged migration, temporarily disable strict missing-declaration enforcement.

```ruby
RecordingStudio.configure do |config|
  config.require_recordable_declarations = false
end
```

This only softens missing declarations into warnings. Invalid declarations and invalid hierarchy writes still raise.
It does not relax capability-owned child validation; undeclared capability children still fail closed.
Re-enable the default `true` setting after every configured type has a declaration.

6. Replace legacy type-label methods with declarations where practical.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true

  def recordable_name
    name
  end
end
```

`recordable_name` remains the preferred instance display-name hook. `recording_studio_label`,
`recordable_type_label`, and `recording_studio_type_label` remain compatibility fallbacks but are no longer the primary
type-label surface.

7. Run the focused validation tests for declaration, hierarchy, and capability-owned child behavior.

```bash
bundle exec ruby -Itest test/recordable_declarations_test.rb
bundle exec ruby -Itest test/capability_owned_recordables_test.rb
bundle exec ruby -Itest test/models/recording_api_methods_test.rb
bundle exec ruby -Itest test/dummy/test/models/commentable_capability_test.rb
```

## Common Upgrade Errors

| Error | Meaning | Fix |
| --- | --- | --- |
| `RecordingStudio::MissingRecordableDeclaration` | A configured ActiveRecord recordable type has no declaration. | Add `recording_studio_recordable(...)` to that model or temporarily set `require_recordable_declarations = false`. |
| `RecordingStudio::InvalidRecordableDeclaration` | A declaration is malformed, references an unregistered parent type, sets `shared: true` without `root: true`, or leaves a non-root type without any valid parent allowance. | Register the parent type in `config.recordable_types`, ensure labels/root/shared flags are valid, and declare `allowed_parent_types:` unless the type is capability-owned. |
| `RecordingStudio::RootNotAllowed` | A child-only recordable was used as a root. | Declare the type with `root: true` if it really is a root, or create it under an allowed parent recording. |
| `RecordingStudio::InvalidParent` | A child was recorded without a parent or under a disallowed parent type. | Pass `parent_recording:` and include that parent's recordable type in `allowed_parent_types:`. |
| `RecordingStudio::OrphanRecording` | A low-level new recording was attempted under an existing root without a parent. | Use `root_recording_for` for root creation or pass `parent_recording:` for child creation. |
| `ArgumentError` | A capability registration declared `child_recordables:` without `source:`. | Add `source:` when registering capability-owned child recordables. |

## Helpful Introspection

```ruby
RecordingStudio.validate_recordable_declarations!
RecordingStudio.recordable_declarations
RecordingStudio.root_recordable_types
RecordingStudio.root_recordable_declarations
RecordingStudio.shared_root_types
RecordingStudio.shared_root_declarations
RecordingStudio.declared_parent_types_for("Page")
RecordingStudio.declared_allowed_parent_types_for("Page")
RecordingStudio.capability_parent_types_for("Comment")
RecordingStudio.capability_allowed_parent_types_for("Comment")
RecordingStudio.recordable_parent_allowances_for("Comment")
RecordingStudio.allowed_parent_types_for("Page")
RecordingStudio.child_recordable_types_for("Page")
RecordingStudio.parent_capabilities_for(child_type: "Comment", parent_type: "Page")
RecordingStudio.parent_allowed?(child_type: "Page", parent_recording: root_recording)
```

Use these helpers in upgrade tests or console checks to confirm that the configured hierarchy matches the app's intended
recording tree.

## Addon Capability Migration

RecordingStudio `3.0.0` makes capability-owned child recordables a core contract. Addons that own internal child
recordables should register them with their capability instead of asking host apps to call implementation-specific child
APIs.

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Host recordables should enable capabilities through mixins:

```ruby
class Page < ApplicationRecord
  include RecordingStudioAccessible::Accessible
end
```

The mixin should call `RecordingStudio.enable_capability(:accessible, on: name)`. Core then derives the effective parent
allowance for `RecordingStudio::Access` under `Page`. Capability-owned child recordables must be registered, declared,
and non-root. `source:` is required when `child_recordables:` is present and is provenance metadata, not an authentication
boundary.

## Adopting the Shared Default Layout

RecordingStudio `3.0.1` ships a reusable layout for addon gems at
`app/views/layouts/recording_studio/default_layout.html.erb`. It provides a
`FlatPack::PageNav::Component` shell with standard Rails layout structure and
safe defaults. Addon controllers can opt in with a single concern include and
a lightweight helper API to configure page nav metadata.

> **Prerequisite:** `flat_pack` (>= 0.1.275) is a required RecordingStudio
> dependency. The layout renders `FlatPack::PageNav::Component` and
> `FlatPack::Alert::Component`. It does not fall back when Flatpack is
> missing. The gem is not on RubyGems; point the host Gemfile at
> `https://github.com/bowerbird-app/flatpack.git` tag `v0.1.275`.
>
> The demo route at `/layout_demo` in the dummy app shows a complete working
> example (see `test/dummy/app/controllers/layout_demo_controller.rb` and
> `test/dummy/app/views/layout_demo/show.html.erb`).

### What the Layout Provides

- `FlatPack::PageNav::Component` rendered at the top of every page.
- Direct page body rendering (no extra content wrapper).
- Standard `yield :head` support for metadata, plus optional
  `default_layout_head` partial auto-detection.
- Automatic OpenGraph tags (og:title, og:type, og:url, og:description,
  og:site_name) for SEO, plus optional `<meta name="description">`.
- Flash notice/alert rendering with `FlatPack::Alert::Component`.
- Configurable app name via `RecordingStudio.configuration.app_name`
  (defaults to `"RecordingStudio"`) used as the `<title>` and `og:site_name`
  fallback.
- Safe defaults: no anchor action, empty right slot, title falls back to
  `RecordingStudio`.

### Opting In

**Step 0 (optional): Configure the app name and data-theme.**

Set a custom app name for `<title>` and `og:site_name` fallback (defaults to
`"RecordingStudio"`):

```ruby
# config/initializers/recording_studio.rb
RecordingStudio.configure do |config|
  config.app_name = "My App"
end
```

The layout applies `data-theme="rounded"` to `<body>`. That value is fixed.

**Step 1: Call the layout macro in your controller.**

```ruby
class WorkspacesController < ApplicationController
  recording_studio_layout { RecordingStudioX.configuration.layout }
end
```

This resolves the layout and makes `RecordingStudio::LayoutHelper` available
in your views. `RecordingStudio::UsesDefaultLayout` was removed in 5.0.0.

> **Note:** `layout` on a subclass replaces the inherited resolver. A
> parent that calls `recording_studio_layout` does not force that layout
> onto a child that declares `layout "application"` or `layout false`.

To keep the resolver and override one action group, declare `layout` with
`only:` or `except:` on that controller. That Rails override wins.

**Step 2: Replace manual breadcrumb and page-chrome markup with the helper API.**

_Before (manual FlatPack breadcrumb and button slots):_

```erb
<% content_for :title, "Workspaces" %>

<%= render FlatPack::Breadcrumb::Component.new(class: "mb-4") do |breadcrumb| %>
  <% breadcrumb.item(text: "Home", href: root_path) %>
  <% breadcrumb.item(text: "Workspaces") %>
<% end %>

<%= render FlatPack::PageTitle::Component.new(
  title: "Workspaces",
  subtitle: "Choose a workspace."
) do |page_title| %>
  <% page_title.actions do %>
    <%= render FlatPack::Button::Component.new(
      text: "New Workspace", style: :primary, url: new_workspace_path
    ) %>
  <% end %>
<% end %>
```

_After (PageNav with helper API):_

```erb
<% recording_studio_page_nav(
  title: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_label: "Home"
) %>

<% recording_studio_page_nav_right do %>
  <%= render FlatPack::Button::Component.new(
    icon: "plus",
    icon_only: true,
    style: :secondary,
    size: :md,
    url: new_workspace_path,
    aria: { label: "Add workspace" }
  ) %>
<% end %>

<%= render FlatPack::PageTitle::Component.new(
  title: "Workspaces",
  subtitle: "Choose a workspace."
) %>
```

For a back-navigation pattern (e.g., a "New" form that navigates back to the
parent list), use `page_nav_back_url` to set the left-side back button:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_back_url: workspaces_path,
  page_nav_back_label: "Workspaces"
) %>
```

You can also combine both sides — the back button on the left and an anchor
or custom actions on the right — they are independent:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_back_url: workspaces_path,
  page_nav_back_label: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_label: "Home"
) %>
```

**Step 3: Remove any existing sidebar or custom layout that duplicates what
the default layout already provides.** The default layout is sidebar-free;
any addon-specific sidebar logic should live in addon layouts, not in the
shared default.

### Helper API Reference

| Method | Purpose |
| --- | --- |
| `recording_studio_page_nav(title:, **slots)` | Sets the page `<title>` and configures PageNav slots. |
| `recording_studio_page_nav_right { ... }` | Renders block content into the PageNav right slot. |
| `default_layout_head { ... }` | Appends block content to the `<head>` element. |
| `recording_studio_seo_description(text)` | Sets `<meta name="description">` and `og:description` tags. |

### Supported Slot Keys

Pass any of these as keyword arguments to `recording_studio_page_nav`:

- `title` — Sets `<title>`. Falls back to `RecordingStudio.configuration.app_name`
  and then to `"RecordingStudio"`.
- `page_nav_anchor_url` — URL for the anchor (close) button. Omit to hide.
  The icon is `x-mark`.
- `page_nav_anchor_label` — Accessible name for the anchor (default: `"Close"`).
- `page_nav_back_url` — URL for the back button. Omit to use browser history
  back. The back button is always rendered, with icon `chevron-left`, style
  secondary, and size md.
- `page_nav_back_label` — Label for the back button (default: `"Go back"`).
- `seo_description` — Set via `recording_studio_seo_description(text)`; renders
  `<meta name="description">` and `og:description` when present.

### Testing Your Layout Adoption

After adopting the default layout, verify your views render correctly:

```ruby
class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  test "index renders default layout with page nav" do
    get workspaces_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Workspaces"
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
  end
end
```

The `data-recording-studio-default-layout="true"` attribute on `<body>` confirms
the layout is active. Assert on your specific nav links, titles, and right-slot
actions as needed.

### Before / After Summary

| Concern | Before (manual) | After (default layout) |
| --- | --- | --- |
| Layout source | Custom per-addon layout or no shared layout | `recording_studio/default_layout` |
| Page chrome | Manual `FlatPack::Breadcrumb::Component` | `FlatPack::PageNav::Component` (automatic) |
| Page nav config | `content_for` scattered across views | `recording_studio_page_nav(...)` helper |
| Right actions | Embedded in `PageTitle` actions slot | `recording_studio_page_nav_right { ... }` |
| Head metadata | Manual `content_for :head` | `default_layout_head { ... }` |
| Flash messages | Per-view or per-layout | Rendered automatically by layout |
| SEO description | Not available | `recording_studio_seo_description(...)` helper |

### Addon Author Notes

If you ship an addon gem with controllers, call `recording_studio_layout`
on each surface's base controller. Return that surface's setting, and
default the setting to `nil`. See
[docs/layouts/default_layout.md](layouts/default_layout.md#gem-adoption).

If your addon needs a sidebar, create a layout that inherits from or wraps
`recording_studio/default_layout` rather than duplicating the PageNav shell.

#### Injecting shared `<head>` content

Sub-gems can provide `recording_studio/_default_layout_head.html.erb` in
their view paths to inject shared `<head>` markup (stylesheets, meta tags,
analytics scripts, etc.) without requiring every consumer view to include
`default_layout_head` blocks. The layout automatically detects and renders
this partial before `yield :head`.

```erb
<%# app/views/recording_studio/_default_layout_head.html.erb %>
```

#### Configuring the app name

Set a custom app name for title and `og:site_name` fallbacks:

```ruby
# config/initializers/recording_studio.rb
RecordingStudio.configure do |config|
  config.app_name = "My App"
end
```

The title fallback chain is:

1. `content_for(:title)` — set per-view
2. `RecordingStudio.configuration.app_name` — configurable globally
3. `"RecordingStudio"` — final hardcoded default

Full documentation is at `docs/layouts/default_layout.md`. A working demo is
available in the dummy app at `/layout_demo`.