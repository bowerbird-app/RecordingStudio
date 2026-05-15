# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bowerbird-app/RecordingStudio/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/bowerbird-app/RecordingStudio/releases/tag/v1.1.0
[1.0.1]: https://github.com/bowerbird-app/RecordingStudio/releases/tag/v1.0.1
[0.2.0]: https://github.com/bowerbird-app/RecordingStudio/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/RecordingStudio/releases/tag/v0.1.0
