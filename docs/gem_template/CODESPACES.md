# RecordingStudio Codespaces And Devcontainer Setup

This repository ships a devcontainer that is also used by GitHub Codespaces. The container boots the dummy app, not a
separate engine UI.

## Quick Start

1. Create the Codespace.
2. Wait for the `postCreateCommand` to finish.
3. Start the dev processes:

```bash
cd test/dummy
bin/dev
```

4. Open the forwarded port 3000.
5. Visit `http://localhost:3000/` or the forwarded URL for the dummy app.

`/recording_studio` is mounted, but the engine currently ships no default routes there.

## What Runs Automatically

`.devcontainer/devcontainer.json` runs:

```bash
bash .devcontainer/post-create.sh
```

That script currently:

- runs `git lfs install`
- runs `npm install`
- installs Playwright Chromium with dependencies
- waits for PostgreSQL on `db:5432`
- changes into `test/dummy`
- runs `bin/setup --skip-server`
- runs `bundle exec rails tailwindcss:build`

The PostgreSQL wait loop exists because container startup can race the database service.

## Container Services

The devcontainer uses Docker Compose with three services:

| Service | Image or build | Purpose |
| --- | --- | --- |
| `db` | `postgres:16` | Dummy app database |
| `redis` | `redis:7-alpine` | Dummy app Redis service |
| `app` | `.devcontainer/Dockerfile` | Main development container mounted at `/workspace` |

The `app` service sets `BUNDLE_PATH=/usr/local/bundle`, and the dummy app's `bin/setup` respects that when present.

## Important Environment Variables

| Variable | Value in the container |
| --- | --- |
| `DB_HOST` | `db` |
| `DB_PORT` | `5432` |
| `DB_USER` | `postgres` |
| `DB_PASSWORD` | `postgres` |
| `DB_NAME` | `app_development` |
| `REDIS_URL` | `redis://redis:6379/0` |
| `CODESPACES` | `true` |

## Running The App

Use the dummy app's `bin/dev`:

```bash
cd test/dummy
bin/dev
```

`test/dummy/Procfile.dev` currently runs:

```text
web: bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
```

## CSRF And Forwarded URLs

The dummy app keeps CSRF tokens enabled in development, but disables strict origin matching so localhost form posts and
forwarded Codespaces URLs work together. That relaxation is for the development environment only.

## Troubleshooting

| Issue | What to try |
| --- | --- |
| `postCreateCommand` fails before the app is ready | Re-run `bash .devcontainer/post-create.sh`. |
| Database connection refused | Confirm the `db` service is healthy, then rerun setup from `test/dummy`. |
| Tailwind output is missing | Run `cd test/dummy && bundle exec rails tailwindcss:build`. |
| Port 3000 is already in use | Start with `cd test/dummy && PORT=3001 bin/dev`. |
| Private or git-sourced dependency fetch fails | See [PRIVATE_GEMS.md](PRIVATE_GEMS.md). |

## Files To Check

- `.devcontainer/devcontainer.json`
- `.devcontainer/post-create.sh`
- `.devcontainer/docker-compose.yml`
- `.devcontainer/Dockerfile`
- `test/dummy/bin/setup`
- `test/dummy/bin/dev`
- `test/dummy/Procfile.dev`
