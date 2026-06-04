# RecordingStudio Local Development

This guide covers local development outside of the devcontainer or Codespaces. If you can use the containerized setup,
that is the fastest path; local setup is primarily for maintainers who want to run the repo directly on their machine.

## Prerequisites

| Dependency | Notes |
| --- | --- |
| Ruby 3.3+ | Required by the gemspec |
| PostgreSQL 16+ | Used by the dummy app |
| Redis 7+ | Used by the dummy app environment |
| Node.js and npm | Required for the dummy app's Tailwind build |

## Standard Setup

From the repository root:

```bash
bundle install
npm install
cd test/dummy
bin/setup --skip-server
bundle exec rails tailwindcss:build
```

Then start the development processes:

```bash
cd test/dummy
bin/dev
```

`bin/dev` runs the Rails server plus the Tailwind watcher from `test/dummy/Procfile.dev`.

## What To Open In The Browser

Use the dummy app at `http://localhost:3000/`.

Useful routes:

- `/`
- `/workspaces`
- `/methods`
- `/capabilities`
- `/tree`

`/recording_studio` is mounted, but the engine currently ships no default UI there.

## Common Commands

Run the top-level test suite:

```bash
bundle exec rake test
```

Run a focused test:

```bash
bundle exec ruby -Itest test/recordable_declarations_test.rb
```

Run RuboCop:

```bash
bundle exec rubocop
```

Reset the dummy database:

```bash
cd test/dummy
bin/rails db:reset
```

Rebuild Tailwind once:

```bash
cd test/dummy
bundle exec rails tailwindcss:build
```

## Environment Variables

| Variable | Default | Notes |
| --- | --- | --- |
| `DB_HOST` | `localhost` | Set to `db` inside the devcontainer/Codespaces |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_USER` | `postgres` | PostgreSQL user |
| `DB_PASSWORD` | `postgres` | PostgreSQL password |
| `DB_NAME` | `app_development` | Dummy app development database |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection URL |
| `PORT` | `3000` | Rails server port |

The dummy app's `bin/setup` honors an existing `BUNDLE_PATH`, which is useful in containers and CI where Bundler is
already configured to install gems into a shared path.

## Troubleshooting

| Issue | What to check |
| --- | --- |
| `PG::ConnectionBad` | Verify PostgreSQL is running and the `DB_*` variables match your local setup. |
| `Redis cannot be reached` | Start Redis locally or update `REDIS_URL`. |
| Tailwind output looks stale | Re-run `bundle exec rails tailwindcss:build` or restart `bin/dev`. |
| Port 3000 is already in use | Start with `PORT=3001 bin/dev`. |
| Bundler installs gems to the wrong path | Check `echo $BUNDLE_PATH` before running `bin/setup`. |

## Files To Check

- `test/dummy/bin/setup`
- `test/dummy/bin/dev`
- `test/dummy/Procfile.dev`
- `test/dummy/config/routes.rb`
