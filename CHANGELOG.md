# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0](https://github.com/bowerbird-app/RecordingStudio/compare/recording_studio-v0.2.0...recording_studio/v0.3.0) (2026-04-09)


### Features

* add capability framework and release automation ([bc1bc5f](https://github.com/bowerbird-app/RecordingStudio/commit/bc1bc5fb182f0dd23bfe7ed0d992647ec06e6526))
* add feature toggles for legacy move/copyable/device sessions ([7a8f02f](https://github.com/bowerbird-app/RecordingStudio/commit/7a8f02f5c09a30f27c318ec93133b99dae98dba9))
* formalize addon capability contract in docs and registration lifecycle ([b47e733](https://github.com/bowerbird-app/RecordingStudio/commit/b47e733358784018f169ae8eb4d7bbcc6cc74e37))
* remove legacy moveable support ([7383c5e](https://github.com/bowerbird-app/RecordingStudio/commit/7383c5ef0c92358368710b27771b6b512cbdd004))


### Bug Fixes

* **ci:** force postgres user in health check ([1b6dbad](https://github.com/bowerbird-app/RecordingStudio/commit/1b6dbad50c83ae383f5e180cfd59e1191eeba4d8))
* **test:** stabilize device session cleanup and ordering assertion ([1ef35d1](https://github.com/bowerbird-app/RecordingStudio/commit/1ef35d1bd4c0055b17eae24ca2acb0b039fc06d8))

## [Unreleased]

## [0.2.0] - 2026-04-09

### Added
- Added legacy feature toggles: `config.features.copyable` and
  `config.features.device_sessions` (both default to `true`).
- Added runtime addon conflict warnings when addon gems are present while matching legacy built-ins are still enabled.
- Added once-per-process deprecation guidance when legacy built-in features are actively used.

### Changed
- Removed legacy built-in move/movable support in favor of the external moveable addon gem.
- Gated legacy copyable capability activation by feature flags.
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

[Unreleased]: https://github.com/bowerbird-app/recording_studio/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bowerbird-app/recording_studio/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/recording_studio/releases/tag/v0.1.0
