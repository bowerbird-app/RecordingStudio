# RecordingStudio Maintainer Docs

This directory keeps repository-maintainer guides that originated in the engine template used to create
RecordingStudio. The path `docs/gem_template/` is historical and is intentionally preserved by `bin/rename_gem`, but
the content in this directory now documents RecordingStudio as it exists today.

## Use These Docs By Audience

Public gem usage:

- [../../README.md](../../README.md)
- [../API_REFERENCE.md](../API_REFERENCE.md)
- [../UPGRADING.md](../UPGRADING.md)

Repository maintenance:

- [CODESPACES.md](CODESPACES.md)
- [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md)
- [INSTALLING.md](INSTALLING.md)
- [CONFIGURATION.md](CONFIGURATION.md)
- [MIGRATIONS.md](MIGRATIONS.md)
- [PRIVATE_GEMS.md](PRIVATE_GEMS.md)
- [CSS_JS_ASSETS_ARCHITECTURE.md](CSS_JS_ASSETS_ARCHITECTURE.md)
- [SERVICES.md](SERVICES.md)
- [SECURITY.md](SECURITY.md)
- [RENAMING.md](RENAMING.md)

## Quick Repository Facts

- Ruby 3.3+ and Rails 8.1+
- The dummy app lives in `test/dummy`
- The usual setup flow is `cd test/dummy && bin/setup --skip-server && bundle exec rails tailwindcss:build`
- Start the demo app with `cd test/dummy && bin/dev`
- Open `http://localhost:3000/` for the demo UI
- `RecordingStudio::Engine` is mounted at `/recording_studio`, but the engine currently ships no default UI or routes

## Documentation Rules

- Keep public API guidance in the root README, `docs/API_REFERENCE.md`, and `docs/UPGRADING.md`
- Use this directory for repository workflows, environment setup, and maintainer-facing notes
- Prefer current repo code, generators, and scripts over template-era assumptions
- If `bin/rename_gem` is used again in the future, manually review this directory because the script intentionally does
   not rewrite files under `docs/gem_template/`
