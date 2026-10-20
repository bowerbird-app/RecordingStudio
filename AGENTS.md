# Recording Studio agent notes

Recording Studio is a Rails engine. Controllers, views, and helpers live in `app/`. The engine, configuration, and version live in `lib/recording_studio`. Generators live in `lib/generators`. Translations live in `config/locales`. Docs live in `docs/`. Engine tests live in `test/`. `test/dummy` is the host app.

## Commands

One engine file:

```bash
bundle exec rake test TEST=test/controllers/workspaces_controller_test.rb
```

Engine suite (`rake test` in the Rakefile, CI job `test`):

```bash
bundle exec rake test
```

Dummy app suite, from `test/dummy` (same CI job):

```bash
bundle exec rails test
```

Lint: `bundle exec rubocop`.

Boot the dummy app from `test/dummy` with `bin/setup --skip-server`, then `bundle exec rails tailwindcss:build`, then `bin/dev` (port 3000).

Version is `RecordingStudio::VERSION` in `lib/recording_studio/version.rb`.

## Working rules

Read files by line range. Search with a narrow path, `grep -l`, or a result limit. Read only the top CHANGELOG entry, never the whole file. Pipe long command output through `tail`. Run the targeted test file or suite before the full suite. Open screenshots only for the final check. Do not run multi-model contests unless the user asks.
