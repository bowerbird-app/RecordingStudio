# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.0.3] - 2026-10-26

### Changed

* Requires `flat_pack` >= 0.1.313. Development and test pin tag `v0.1.313`.

### Upgrade notes

- Pin `flat_pack` tag `v0.1.313` and run `bundle update flat_pack`.
- The default layout is unchanged. Flash still renders with `FlatPack::Alert`.
  `FlatPack::Flash` stays opt-in.
- `DateInput` and `DateRangeInput` keep the same public kwargs and HTML.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-603).

## [6.0.2] - 2026-10-26

### Fixed

* Host stylesheets load `flat_pack/variables`, `flat_pack/application`, and
  `flat_pack/rich_text` before the Tailwind sheet. The viewport meta includes
  `viewport-fit=cover`. The dummy Tailwind entry scans the installed gem and
  leaves font and radius tokens in `flat_pack/variables`. `application.js`
  calls `initLocalTimes`.
* Dummy cards use Flatpack's default card padding. Section titles inside a
  card use `size: :md` and `spacing: :none`. Stacked blocks use `Grid` or
  `Collection` gap. Flatpack components do not take margin utilities such
  as `mb-4`. Form actions use `Collection` `layout: :wrap`.

### Upgrade notes

- Link the three Flatpack stylesheets, then the host Tailwind sheet.
- Add `viewport-fit=cover` to the viewport meta tag.
- Point Tailwind `@source` at the gem. Do not copy `--font-*` or `--radius-*`
  into the host sheet, and do not add `--color-fp-*`.
- Import `initLocalTimes` from `flat_pack/local_time` and call it on
  `DOMContentLoaded` and `turbo:load`.
- Do not pass `padding: :none` on a card to inset its header. Omit it.
  Inside a card, pass `SectionTitle` `size: :md, spacing: :none`.
  `class: "my-0"` does not override the title's spacing.
- Do not pass margin utilities on Alert or other Flatpack components.
  Alert, Breadcrumb, PageTitle, and `page_nav_button_group` have no spacing prop.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-602).

## [6.0.1] - 2026-10-26

### Changed

* Requires `flat_pack` >= 0.1.311. Development and test pin tag `v0.1.311`.
  `view_component` resolves to 4.19.0 (`>= 4.14`, `< 5`).

### Upgrade notes

- Pin `flat_pack` tag `v0.1.311` and run `bundle update view_component`.
  Render each component instance once. A second render raises
  `ViewComponent::ReusedInstanceError`. Remove
  `include ViewComponent::ExperimentallyCacheable`. See
  [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-601).

## [6.0.0] - 2026-10-23

### Breaking

* The default layout is `FlatPack::PageLayout` (`width: :default`). The
  top bar uses the default `top_nav_width: :content` and the default
  `content_scroll: :below`, so the row matches the column and sits above
  the title. `FlatPack::TopNav` uses `padding: :none`. Back and close come
  from `flat_pack_page_nav(round: true)` / `flat_pack_page_nav_tag` as two
  round buttons. Page actions come from `register_page_nav` and one
  `page_nav_button_group` (`variant: :outlined`, ghost `sm` for every role,
  `collapse: :menu`) on the right. Below 768px that group is the only phone
  menu. The title and subtitle render as `FlatPack::PageTitle`. `<html>` is
  `data-theme="rounded"`.
* `recording_studio_page_nav`, `recording_studio_page_nav_right`, and the
  `page_nav_*` content_for slots are removed. Views set `content_for :title`
  and `content_for :subtitle`.
* Requires `flat_pack` >= 0.1.310. There is no compatibility shim.

### Changed

* Development and test pin `flat_pack` to tag v0.1.310. The dummy sign-in
  card passes `background: :shaded`, and page titles use `slot`. The dummy
  Tailwind file sources Flatpack components and helpers and does not fork
  `--color-fp-*`.

### Upgrade notes

- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-600).

## [5.1.0] - 2026-10-23

### Added

* `recordings.event_created` payloads include `metadata`, a frozen copy of the event's metadata with
  string keys. It is `{}` when that metadata is nil or empty. Existing payload keys,
  `schema_version`, and actor and impersonator semantics are unchanged.

## [5.0.0] - 2026-10-21

### Breaking

* `RecordingStudio::UsesDefaultLayout` is removed. Engine and host controllers
  call `recording_studio_layout { Gem.configuration.layout }`. The macro defines
  `recording_studio_resolved_layout` and declares
  `layout :recording_studio_resolved_layout`, so subclasses inherit it through
  Rails. `include` no longer has to run again on each subclass.
* Lookup order is the block's setting when it is not `nil`, then
  `RecordingStudio.configuration.layout` when that is not `nil`, then
  `RecordingStudio::DEFAULT_LAYOUT` (`"recording_studio/default_layout"`).
  `RecordingStudio::ApplicationController` uses that same default. It no longer
  falls back to `"application"`.
* A layout callable is invoked as `call(controller:)` only. It returns a
  String (that layout), `nil` (try the next level), or `false` (no layout).
  A positional parameter raises `ArgumentError`. `configuration.layout = false`
  is allowed and means no layout.
* `layout "name"` or `layout false` on a controller still replaces the
  inherited resolver.
* `recording_studio/action_layout` is removed, along with
  `recording_studio/shared/page_nav` and the dummy action-layout demo.
  Show, new, and edit screens use the default layout.
* The default layout keeps back and anchor only. It no longer reads
  `:body_theme`, `:seo_image`, or page-nav icon, style, and size slots.
  `recording_studio_seo_image` is removed. `:title`, `:head`,
  `:seo_description`, back and anchor URL and label, `:page_nav_right`,
  Flatpack stylesheets, and flash alerts stay, because gem views set them.
* `flat_pack` (>= 0.1.275) is a required dependency. The default layout
  renders `FlatPack::PageNav::Component` for back and anchor and drops the
  no-Flatpack fallback. `flat_pack` is not on RubyGems. The gemspec declares
  the dependency; the Gemfile pins
  `https://github.com/bowerbird-app/flatpack.git` tag `v0.1.275`.

### Added

* `RecordingStudio::Layout.hardcoded_layout_paths(root, ignore: [])` and
  `rake recording_studio:check_layouts` report controllers that hard-code
  `layout "recording_studio/..."`.
* Host layout contract in `docs/layouts/default_layout.md`: `content_for`
  slots, Flatpack stylesheets, and flash alerts gem views rely on.
  `FlatPack::SidebarLayout` is the application shell. Flatpack does not ship
  a `PageLayout` component; the page shell is `recording_studio/default_layout`.

### Upgrade notes

- Replace `include RecordingStudio::UsesDefaultLayout` with
  `recording_studio_layout`. See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-500).

## [4.7.1] - 2026-10-20

### Fixed

* The default layout page nav uses Flatpack's ordered row API (`with_back`,
  `with_close`, `with_item`). `page_nav_back_url` is the back control's href.
  Slot labels are tooltips. This requires `flat_pack` >= 0.1.274.
* The dummy sign-in card uses `FlatPack::Card` style `:shaded`. Flatpack
  0.1.275 rejects `:elevated`.

### Added

* `RecordingStudio.configuration.layout` sets the layout for core controllers
  that serve views. A String is a layout name. A lambda or proc is called with
  `controller:`. Leave it unset to keep the current layout.

### Changed

* Development and test pin `flat_pack` to tag v0.1.275.

### Upgrade notes

- No migration is required. Host apps need no change unless they override a
  core layout or the page nav partial.
- Hosts that copy `recording_studio/shared/_default_layout` or pass removed
  `FlatPack::PageNav` keywords (`back_icon`, `back_label`, `back_style`,
  `back_size`, `anchor_icon`, `anchor_label`, `anchor_href`, `right_slot`)
  must use the Flatpack >= 0.1.274 row API.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-471).

## [4.7.0] - 2026-10-14

### Added

* `RecordingStudio::Translation.register_shipped_english(path)` so addon
  engines can contribute their own `config/locales/en.yml` to the final
  shipped-English fallback table (deep-merged with base, de-duplicated by
  expanded path; missing or malformed files skipped; registrations persist
  across reload; boot-time registration only)
* README / API docs for engine initializer usage, RecordingStudio `>= 4.7`,
  and an optional `respond_to?(:register_shipped_english)` guard

### Upgrade notes

- No migration is required. Host apps need no change.
- Addon engines that ship `recording_studio.<gem>.*` English should call
  `RecordingStudio::Translation.register_shipped_english` from an engine
  initializer at boot (typically
  `before: "recording_studio.load_shipped_english"`), not at request time, so
  keys remain available after the loaded `:en` backend is pruned. Pin
  RecordingStudio `>= 4.7`, or guard with
  `respond_to?(:register_shipped_english)`.
- Fallback order is unchanged: loaded `:en`, then caller `default:`, then the
  merged shipped table. Present keys stay byte-identical to `I18n.t`.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-470).

## [4.6.1] - 2026-10-14

### Added

* Boot and reload coverage for the eager-loaded gem English table (initializer
  load and `to_prepare` reset); missing shipped `en.yml` returns an empty
  frozen table and `RecordingStudio.t` matches `I18n.t`

### Upgrade notes

- No migration or host code change is required. Runtime behavior is unchanged
  from 4.6.0.

## [4.6.0] - 2026-10-13

### Added

* English fallback for shipped `recording_studio.*` keys when the active locale
  has no translation: `RecordingStudio.t` / `RecordingStudio::Translation.t`
  resolve the loaded `:en` translation via `locale: :en` (host English
  overrides included), then the caller's `default:`, then an eager-loaded,
  deep-frozen copy of the gem's own `config/locales/en.yml` (reset on Rails
  code reload)
* Layout / page-nav views and `Labels.empty_label` look up copy through
  `RecordingStudio.t` so fallback English comes from the loaded `:en` backend
  or the gem-shipped table (no hand-copied Ruby string defaults that can drift)
* Behavioral coverage: a locale with no translations renders loaded English on
  default layout, non-FlatPack page-nav fallback, pure HTML chrome fallback,
  action page nav, and Labels; a boot-loaded host French override wins on real
  renders; English renders stay identical to prior gem English; keys deleted
  from the loaded backend still render the gem-shipped English (not
  "Translation missing", not a 500)

### Upgrade notes

- No migration or host code change is required for English.
- Hosts that enable raise-on-missing translations no longer raise for
  gem-shipped `recording_studio.*` keys looked up through `RecordingStudio.t`
  (or the call sites above) when loaded `:en` or the gem-shipped table has the
  key. Host overrides in the active locale still win; host `:en` overrides win
  on the loaded-English fallback step.
- Partial pluralization in a non-English locale (for example French with only
  `one`) still raises `I18n::InvalidPluralizationData` — the English fallback
  does not fill missing plural keys.
- A missing `_html` key with a non-interpolating caller `default:` stays
  unsafe like view `t`. An interpolating caller `default:` escapes args and
  returns `html_safe` (stricter than view `t`).
- `en.yml` is unchanged. Prefer `RecordingStudio.t` for gem keys when adding
  new call sites so missing locales keep the same fallback.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-460).

## [4.5.0] - 2026-10-12

### Added

* English Rails I18n key for the Labels empty marker
  (`recording_studio.core.labels.empty` → `"—"`)
* `RecordingStudio::Labels.empty_label` resolves the empty marker through
  `I18n.t` at call time (honors `I18n.locale`; not memoized)
* Host English override coverage: test-only fixture
  `test/dummy/test/locales/core_host_override.en.yml` plus an integration test
  that appends it last to `I18n.load_path`, reloads, asserts nested
  `recording_studio.core.*` keys win on layout demo and Labels, then restores
  the load path
* Locale regression: every `lib/**/*.rb` file must not mention
  `i18n.load_path` / `I18n.load_path`
* Non-FlatPack PageNav fallback render test asserts literal English chrome

### Changed

* `Labels.name_for` / `label_for` / `type_label_for` / `type_plural_label_for` /
  `title_for` return the I18n-resolved empty label when the recordable is
  blank (English output unchanged). The public `EMPTY_LABEL` constant remains
  the English `"—"` literal for hosts that reference it directly.
* Those helpers return an unfrozen I18n string, not the frozen `EMPTY_LABEL`
  constant object — identity / `frozen?` checks against the constant no longer
  hold. Compare with `Labels.empty_label` instead.
* Layout / page-nav `t(...)` calls pass `default:` with the original English
* `.release-please-manifest.json` aligned to the shipped gem version

### Fixed

* `Labels.label_for` is a module function again (the `alias` after
  `module_function` left only an instance method, so
  `RecordingStudio::Labels.label_for(...)` raised `NoMethodError`)
* `Recording#name` / `Recording#label` compare against `Labels.empty_label`
  (call-time) so a translated empty marker still falls back to the type label

### Upgrade notes

- No migration or host code change is required for English.
- To translate or override the empty label, set
  `recording_studio.core.labels.empty` in the host's locale files.
- Prefer `Labels.empty_label` (or the label helpers) over comparing against
  `Labels::EMPTY_LABEL` when the active locale may not be English, and do not
  rely on object identity or `frozen?` against the constant.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-450).

## [4.4.0] - 2026-10-09

### Added

* English Rails I18n keys for static interface copy in the gem's own layout
  shells and `page_nav` partial (`config/locales/en.yml` under
  `recording_studio.core`)

### Changed

* Default PageNav labels and nav aria-labels in
  `recording_studio/shared/_default_layout` and
  `recording_studio/shared/_page_nav` resolve through `t(...)` (English output
  unchanged)

### Upgrade notes

- No migration or host code change is required for English.
- To translate or override the defaults, add keys under
  `recording_studio.core.navigation` in the host's locale files.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-440).

## [4.3.0] - 2026-10-08

### Added

* Shared layout shells under `app/views/recording_studio/shared/` —
  `default_layout` is now a thin public wrapper over
  `shared/_default_layout` (rendered output unchanged from 4.2.x)
* `rails g recording_studio:views RESOURCE` FlatPack scaffold templates

### Upgrade notes

- 5.0.0 removes the TopNav layout added in this release. See
  [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-500).

## [4.2.1] - 2026-09-02

Cloud Agent install no longer fails a warm environment rebuild. Skills still
fetch at Build.

### Added

* `.cursor/environment.json`, `.cursor/install.sh`, `.cursor/fetch-skills.sh`,
  and `.cursor/start.sh` for Cloud Agent Builds

### Fixed

* `.cursor/install.sh` skips apt, ruby-build, db:prepare, and tailwind when
  Ruby, bundle, and Postgres are already usable. A skippable provision
  failure no longer fails the Build. Fetch-skills always runs last.

### Upgrade notes

- No host or schema changes. Rebuild the Cloud Agent environment with Draft
  off so Build loads the pack.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-421).

## [4.2.0] - 2026-08-21

### Added

* `RecordingStudio::Capabilities.include_for(:name, **options, &block)` enablement factory
* Dummy `RecordingStudio::Capabilities::Commentable.to` wrapper as the host include verb

### Changed

* Hosts enable mixin capabilities with `include RecordingStudio::Capabilities::<Name>.to(**opts)`
* Dummy commentable enablement moved from `.with` to `.to`

### Migration Notes

- Installing a mixin gem still does not enable the capability; per-type opt-in is unchanged.
- Parent rules stay on `recording_studio_recordable`.
- Mixin authors should wrap `include_for` as a thin `.to`. Option validation and `register_capability` stay in the mixin, not in core.
- Direct `enable_capability` / `set_capability_options` calls still work.
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-420).

## [4.1.0] - 2026-08-20

### Added

* `shared:` on `recording_studio_recordable` for root types that are domain forests rather than owned buckets
* `RecordingStudio.shared_root_type?`, `shared_root_types`, `shared_root_declarations`, `shared_root?`, and `shared_root_tree?`
* `recording.shared_root?` and `recording.shared_root_tree?` tree helpers

### Changed

* capability-owned children can no longer use a shared root as a direct parent; domain children still can via `allowed_parent_types`

### Migration Notes

- Existing roots are unchanged (`shared:` defaults to `false`).
- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-410) to declare a Messages-style shared root.
- Enable Accessible and other capability-owned children on objects below the shared root, not on the shared root itself.

## [4.0.0] - 2026-08-15

### ⚠ BREAKING CHANGES

* remove `Recording.default_scope` ordering; use `Recording.recent` (or an explicit `order:`) when newest-first is required
* make `RecordingStudio::Event` append-only (AR update/destroy raise); purge history with SQL `delete_all` or recording `dependent: :delete_all`
* reject Relation/Arel/proc recordable query escape hatches unless `config.allow_unsafe_recordable_queries = true` or `allow_unsafe_recordable_query: true`
* `revert` requires `to_recordable` to appear in that recording's event history
* remove template `RecordingStudio::Services::ExampleService`

### Added

* unique root-recording index per recordable (`parent_recording_id IS NULL`)
* composite indexes for root/parent/recordable lookups and event timeline/actor/action filters
* recursive CTE tree helpers for ancestors/descendants
* `config.require_actor`, `config.authorize_write`, `config.max_metadata_bytes`, `config.allow_unsafe_recordable_queries`
* `before_record` / `after_record` hooks on `RecordingStudio.record!`
* race-safe `root_recording_for` and idempotent event create via `RecordNotUnique` rescue
* shared warning helpers, metadata normalization, and query relation window helper

### Changed

* recording destruction uses `dependent: :delete_all` for events so intentional purges bypass append-only AR guards
* Labels body-snippet naming is declaration-driven instead of hard-coded Comment type lists
* install migrations include hardened indexes; incremental `harden_recording_studio_indexes_and_constraints` migration is idempotent

### Migration Notes

- See [docs/UPGRADING.md](docs/UPGRADING.md#upgrading-to-400) for the `3.x` to `4.0.0` upgrade path.
- Run `rails g recording_studio:migrations` (or install the harden migration) and `rails db:migrate`.
- Replace implicit `Recording` ordering with `.recent` or explicit order hashes.
- Opt in to unsafe recordable query APIs where addon code passes Relation/Arel/procs.
- Enable `config.require_actor = true` and optionally `config.authorize_write` in production hosts.

## [3.0.3] - 2026-07-20

### Changed

* bump gem version to `3.0.3`
* refresh dummy app bundle references to track the current engine version
* align maintainer documentation and markdown guidance with the current release state

## [3.0.2] - 2026-07-20

### Changed

* bump gem version to `3.0.2`
* refresh dummy app bundle references to track the current engine version
* align maintainer documentation and markdown guidance with the current release state

## [3.0.1] - 2026-06-26

### Added

* add shared default layout (`recording_studio/default_layout`) with `RecordingStudio::UsesDefaultLayout` concern and `RecordingStudio::LayoutHelper` for addon gems
* add `docs/layouts/default_layout.md` with full usage guide and slot contract reference
* add dummy app demo route at `/layout_demo` showing default layout with PageNav, right slot, and head metadata
* add test coverage for layout helper, layout rendering, and initializer wiring
* add `RecordingStudio.configuration.app_name` for customizable `<title>` and `og:site_name` fallback (defaults to `"RecordingStudio"`)
* add OpenGraph meta tag support (og:title, og:type, og:url, og:description, og:image, og:site_name) with automatic rendering
* add `recording_studio_seo_description` and `recording_studio_seo_image` helper methods for SEO metadata
* add optional `recording_studio/_default_layout_head` partial auto-detection for sub-gem `<head>` injection

### Migration Notes

- See [docs/UPGRADING.md#adopting-the-shared-default-layout](docs/UPGRADING.md#adopting-the-shared-default-layout) for guidance on adopting the shared default layout in your addon controllers and views.

## [3.0.0](https://github.com/bowerbird-app/RecordingStudio/compare/recording_studio/v2.0.0...recording_studio/v3.0.0) (2026-06-04)

### ⚠ BREAKING CHANGES

* require recordable declarations for configured types and fail closed for capability-owned child recordables
* require addon-owned child recordables to be registered with `source:` and `child_recordables:` and remain non-root

### Features

* enforce declaration-based hierarchy rules across root and child recording creation paths
* derive capability-owned child parent allowances from enabled capabilities and expose new parent-introspection helpers
* add dummy app and test coverage for `commentable` pages owning `RecordingStudioComment` children
* update README, API reference, generated install docs, and upgrade guidance for declaration-enforced hierarchies and capability-owned child recordables

### Bug Fixes

* block undeclared capability-owned child recordables from inheriting root or parent allowance through legacy fallback behavior
* tighten validation and test assertions so invalid child registration and parent allowance failures are isolated correctly

### Migration Notes

- See [docs/UPGRADING.md](docs/UPGRADING.md) for the full `2.0.0` to `3.0.0` upgrade path.
- Host apps must declare every configured recordable type and stop creating child-only recordables as roots.
- Addons that own internal child recordables must register them through `RecordingStudio.register_capability(..., source:, child_recordables:)` and enable the capability on host recordables.

## [2.0.0](https://github.com/bowerbird-app/RecordingStudio/compare/recording_studio-v1.2.0...recording_studio/v2.0.0) (2026-06-02)


### ⚠ BREAKING CHANGES

* remove built-in access control from core

### Features

* add capability framework and release automation ([bc1bc5f](https://github.com/bowerbird-app/RecordingStudio/commit/bc1bc5fb182f0dd23bfe7ed0d992647ec06e6526))
* add feature toggles for legacy move/copyable/device sessions ([7a8f02f](https://github.com/bowerbird-app/RecordingStudio/commit/7a8f02f5c09a30f27c318ec93133b99dae98dba9))
* formalize addon capability contract in docs and registration lifecycle ([b47e733](https://github.com/bowerbird-app/RecordingStudio/commit/b47e733358784018f169ae8eb4d7bbcc6cc74e37))
* remove built-in access control from core ([c6d7f00](https://github.com/bowerbird-app/RecordingStudio/commit/c6d7f0038fb44bb6928e1831545f18c9cf7f2242))
* remove legacy moveable support ([7383c5e](https://github.com/bowerbird-app/RecordingStudio/commit/7383c5ef0c92358368710b27771b6b512cbdd004))


### Bug Fixes

* **ci:** force postgres user in health check ([1b6dbad](https://github.com/bowerbird-app/RecordingStudio/commit/1b6dbad50c83ae383f5e180cfd59e1191eeba4d8))
* **test:** stabilize device session cleanup and ordering assertion ([1ef35d1](https://github.com/bowerbird-app/RecordingStudio/commit/1ef35d1bd4c0055b17eae24ca2acb0b039fc06d8))

## [1.2.0] - 2026-05-15

### Added
- Added cohesive top-level recordable display helpers: `RecordingStudio.recordable_name`,
  `RecordingStudio.recordable_type_label`.

### Changed
- Updated the addon-first docs and dummy method catalog to present identity and display-label helpers as one cohesive
  public API spanning both `RecordingStudio` and `RecordingStudio::Recording`, while keeping older label/title helpers
  available as compatibility aliases.
- Expanded the documentation with an agent-focused API reference that lists public methods, parameters, return values,
  and the intent behind each supported write, query, capability, label, and hook helper.

## [1.1.0] - 2026-05-06

### Added
- Added stable addon-facing helper APIs in core for recordable identity, root-recording relationships, duplication, and
  polymorphic counter cache updates.
- Added explicit addon extension points for per-type recordable duplication strategies and label/presentation formatters.

### Changed
- Refactored `RecordingStudio::Recording` into smaller concerns so hierarchy, query, duplication, counter, identity, and
  presentation responsibilities are easier to extend and audit.
- Separated identity helpers from presentation helpers so addons can resolve types and roots without depending on UI
  label heuristics.
- Documented the addon-first public API surface, trusted extension points, and migration guidance for addon authors.

### Migration Notes
- Prefer `RecordingStudio.recordable_type_name`, `RecordingStudio.resolve_recordable_type`,
  `RecordingStudio.root_recording_or_self`, and `RecordingStudio.assert_recording_belongs_to_root!` in addons instead of
  reimplementing `safe_constantize` or `root_recording || self` patterns.
- Prefer `config.register_recordable_dup_strategy(...)` and `RecordingStudio::Labels.register_formatter(...)` over
  monkey-patching core internals.

## [1.0.1] - 2026-05-04

### Removed
- **BREAKING**: Removed all trash-related functionality from core gem (moved to RecordingStudio_trashable addon).
  - Removed `RecordingStudio::RecordingTrashable` module and related concerns.
  - Removed `RecordingStudio::Capabilities::Trashable` capability.
  - Removed `RecordingStudio::Addons::Trashable` addon loader.
  - Removed `trashed_at` column from recordings table in fresh migrations.
  - Removed `include_children` configuration option (now handled by addon).
  - Removed `trash`, `restore`, and `hard_delete` methods from Recording model.
  - Removed `trashed`, `including_trashed`, and `include_trashed` scopes from Recording model.
  - Removed trash-related counter cache adjustments.
  - Updated dummy app to remove trash functionality references.
- Removed built-in access-control recordables, access services, device-session persistence, legacy feature flags,
  related dummy app flows, and their documentation from core.

### Changed
- Changed `recording_studio:migrations` to install the current core schema by default for fresh apps, with `--full_history` available for older apps that need the historical engine migration chain.
- Updated documentation to note that trash behavior lives in RecordingStudio_trashable addon gem.

## [0.2.0] - 2026-04-09

### Added
- Added legacy feature toggles for built-in extracted capabilities.
- Added runtime addon conflict warnings when addon gems are present while matching legacy built-ins are still enabled.
- Added once-per-process deprecation guidance when legacy built-in features are actively used.

### Changed
- Removed legacy built-in move/movable support in favor of the external moveable addon gem.
- Gated legacy device session tracking so it can be disabled without cookie/session side effects.
- Documented migration guidance for disabling legacy built-ins when using addon gems.
- Refactored recordable naming terminology to prefer `recordable_name`, `recordable_type_label`, `recording.name`, and `RecordingStudio::Labels.name_for`, while keeping legacy label methods as compatibility aliases.

## [0.1.0] - 2025-12-04

### Added
- Initial release
- Rails mountable engine structure
- PostgreSQL with UUID primary keys support
- TailwindCSS v4 integration
- GitHub Codespaces devcontainer configuration
- Docker Compose setup with PostgreSQL and Redis
- Install generator for host applications
- Comprehensive README and documentation
- Basic test suite with Minitest

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio/compare/v4.7.0...HEAD
[4.7.0]: https://github.com/bowerbird-app/RecordingStudio/compare/v4.6.1...v4.7.0
[4.6.1]: https://github.com/bowerbird-app/RecordingStudio/compare/v4.6.0...v4.6.1
[4.6.0]: https://github.com/bowerbird-app/RecordingStudio/compare/v4.5.0...v4.6.0
[4.5.0]: https://github.com/bowerbird-app/RecordingStudio/compare/v4.4.0...v4.5.0
