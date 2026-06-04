# `bin/rename_gem`

RecordingStudio still ships the template-era rename helper. It can rename the gem throughout the repository, but it is
now a maintainer tool rather than part of the runtime gem API.

## Usage

```bash
bin/rename_gem new_name
bin/rename_gem new_name --dry-run
bin/rename_gem new_name --from recording_studio
```

The script normalizes names to snake_case and derives the PascalCase constant automatically.

## How Current Detection Works

If `--from` is omitted, the script tries to detect the current gem name from:

1. the `.gemspec` filename
2. the gemspec's `spec.name`
3. the first matching directory under `lib/`

## What The Script Updates

The script currently:

- rewrites file contents in relevant `.rb`, `.md`, `.gemspec`, `.erb`, `.sh`, `.yml`, and related files
- renames files whose names include the old gem name
- renames key directories such as `lib/<name>` and `lib/generators/<name>` when they exist
- updates selected dummy-app files such as `test/dummy/Gemfile` and `test/dummy/config/routes.rb`

## Important Exclusions

The current script intentionally excludes:

- `docs/gem_template/` from content replacement
- most of `test/dummy/` except a small whitelist
- files listed in `EXCLUDED_FILES`

That means a successful rename still requires manual review of the maintainer docs in `docs/gem_template/`.

## Resume Support

The script saves progress in `.rename_state.yml` and can resume after interruptions. The phases are:

1. update file contents
2. validate remaining references
3. rename files
4. rename directories

If a previous rename state conflicts with the new request, the script prompts before deleting the old state.

## Recommended Workflow

1. Run a dry run.

```bash
bin/rename_gem new_name --dry-run
```

2. Run the real rename.

```bash
bin/rename_gem new_name
```

3. Review the diff and manually inspect `docs/gem_template/`.
4. Run the test suite.

```bash
bundle exec rake test
```

## Files To Check

- `bin/rename_gem`
- `.gitignore`
- `docs/gem_template/`
