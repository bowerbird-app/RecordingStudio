# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Removed
- Removed a legacy built-in capability from core, tests, and current documentation.

## [0.2.0] - 2026-04-09

### Added
- Added legacy feature toggles for built-in extracted capabilities and `config.features.device_sessions`
  (both default to `true`).
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

[Unreleased]: https://github.com/bowerbird-app/recording_studio/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bowerbird-app/recording_studio/releases/tag/v0.2.0
[0.1.0]: https://github.com/bowerbird-app/recording_studio/releases/tag/v0.1.0
