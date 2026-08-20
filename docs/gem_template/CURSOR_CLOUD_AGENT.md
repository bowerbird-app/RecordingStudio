# RecordingStudio Cursor Cloud Agent Environment

This repository ships a [Cursor Cloud Agent](https://cursor.com/docs/cloud-agent/setup) environment under
`.cursor/`. It boots the dummy Rails app (`test/dummy`) with a local PostgreSQL server so an agent can run the app and
the test suite end to end.

Unlike the Codespaces/devcontainer setup (see [CODESPACES.md](CODESPACES.md)), a Cloud Agent runs in a **single
container**, so PostgreSQL runs inside the same image rather than as a separate Docker Compose service.

## What ships in `.cursor/`

| File | Purpose |
| --- | --- |
| `environment.json` | Declares the image build, the bootstrap/boot commands, the `rails-dev` terminal, and forwarded ports. |
| `Dockerfile` | Base image (`ruby:3.3-slim-bookworm`) with the Ruby toolchain, PostgreSQL, Node.js, and build libraries. |
| `install.sh` | One-time repository bootstrap: installs gems, prepares the database, builds Tailwind, and seeds demo data. |
| `start.sh` | Per-boot step: starts PostgreSQL and waits until it accepts connections. |
| `lib.sh` | Shared helpers (database defaults, `start_postgres`, `ensure_postgres_password`). |

## Lifecycle

1. **Image build** – the `Dockerfile` installs the stable system dependencies once.
2. **Install** (`install.sh`) – after the source is checked out, it starts PostgreSQL, runs `bundle install` for both the
   gem and `test/dummy`, runs `bin/rails db:prepare`, builds Tailwind, and seeds the development database. With
   environment builds enabled this runs once and is baked into the snapshot.
3. **Start** (`start.sh`) – on every boot it brings PostgreSQL back up.
4. **`rails-dev` terminal** – runs `bin/dev` (`test/dummy/Procfile.dev`), i.e. the Rails server on `0.0.0.0:3000` plus
   the Tailwind watcher.

## Ports and URLs

| Port | Service |
| --- | --- |
| 3000 | Rails server (dummy app) |
| 5432 | PostgreSQL |

Open `http://localhost:3000/`. You are redirected to the sign-in page when signed out.

Useful routes: `/`, `/workspaces`, `/methods`, `/capabilities`, `/tree`. `/recording_studio` is mounted but ships no
default UI.

## Seeded sign-in accounts

`install.sh` seeds three users through `test/dummy/db/seeds.rb`:

| Email | Role |
| --- | --- |
| `admin@example.com` | Admin |
| `avery@example.com` | Editor |
| `quinn@example.com` | Writer |

The password comes from `DUMMY_SEED_PASSWORD` (default `password` in this environment). It is a throwaway local
credential for the sandbox only.

## Database settings

The dummy app reads the same `DB_*` variables documented in [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md). The Cloud Agent
defaults are:

| Variable | Default |
| --- | --- |
| `DB_HOST` | `localhost` |
| `DB_PORT` | `5432` |
| `DB_USER` | `postgres` |
| `DB_PASSWORD` | `postgres` |
| `DB_NAME` | `app_development` |

Redis is not required: development Action Cable uses the `async` adapter.

## Running things by hand

```bash
# From the repository root
cd test/dummy
bin/dev                       # Rails server + Tailwind watcher

bundle exec rails tailwindcss:build   # rebuild CSS once
bin/rails db:reset                    # reset the dummy database
```

Run the suites the same way CI does:

```bash
# Gem tests (repository root)
bundle exec rake test

# Dummy app tests
cd test/dummy && bundle exec rails test
```

## Troubleshooting

| Issue | What to try |
| --- | --- |
| `PG::ConnectionBad` | Re-run `.cursor/start.sh` to start PostgreSQL, then retry. |
| Server errors about pending migrations after switching branches | Run `cd test/dummy && bin/setup --skip-server`. |
| Tailwind output looks stale | Run `cd test/dummy && bundle exec rails tailwindcss:build`. |
| Port 3000 already in use | Start with `cd test/dummy && PORT=3001 bin/dev`. |
| Private/git-sourced dependency fetch fails | See [PRIVATE_GEMS.md](PRIVATE_GEMS.md). |

## Files to check

- `.cursor/environment.json`
- `.cursor/Dockerfile`
- `.cursor/install.sh`
- `.cursor/start.sh`
- `.cursor/lib.sh`
- `test/dummy/bin/dev`
- `test/dummy/Procfile.dev`
