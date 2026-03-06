> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/gem_template](https://github.com/bowerbird-app/gem_template/tree/main/docs/gem_template)
> *   **Last Updated:** December 12, 2025
>
> *Maintainers: Please update the date above when modifying this file.*

---

# GitHub Codespaces Setup

This document covers how the devcontainer is configured and how to work in GitHub Codespaces.

---

## Quick Start

1. **Create a Codespace** on this repository (click the green "Code" button → "Codespaces" → "Create codespace on main").
2. **Wait** for the container to build and the `postCreateCommand` to complete (3-5 minutes).
3. **Start the development server**:
   ```bash
   cd test/dummy
   bin/dev
   ```
4. **Open the app** – click the forwarded port 3000 in the "Ports" tab.
5. **Visit the engine** at `/gem_template`.

---

## What Runs Automatically

The `postCreateCommand` in `.devcontainer/devcontainer.json` executes:

```bash
bash .devcontainer/post-create.sh
```

That script:
- Installs Git LFS (if needed)
- Installs Node dependencies
- Installs Playwright Chromium and its system packages
- Waits for PostgreSQL to become reachable on `db:5432`
- Installs gem dependencies
- Prepares the PostgreSQL database (creates, migrates, and seeds as needed via `db:prepare`)
- Builds TailwindCSS assets

The explicit wait is important because Codespaces can start the app container before the sibling database service is fully reachable, even when Docker Compose health checks are configured.

---

## Docker Compose Services

The devcontainer uses Docker Compose with three services defined in `.devcontainer/docker-compose.yml`:

| Service | Image | Port | Notes |
|---------|-------|------|-------|
| **db** | `postgres:16` | 5432 | UUID support via `pgcrypto`; volume `pgdata` |
| **redis** | `redis:7-alpine` | 6379 | Volume `redis_data` |
| **app** | Built from `.devcontainer/Dockerfile` | 3000 | Ruby 3.3 slim; mounts `/workspace` |

Health checks ensure dependent services are ready before Rails boots.

---

## Environment Variables

Set automatically inside the container:

| Variable | Value |
|----------|-------|
| `DB_HOST` | `db` |
| `DB_PORT` | `5432` |
| `DB_USER` | `postgres` |
| `DB_PASSWORD` | `postgres` |
| `REDIS_URL` | `redis://redis:6379/0` |
| `CODESPACES` | `true` |

---

## Private Gem Access

This gem template may depend on private gems hosted in GitHub repositories under the `bowerbird-app` organization.

### In Codespaces

The environment variable `BOWERBIRD_ORG_CODESPACE_TOKEN` is automatically configured as a **Codespaces secret** at the organization level. This token:

- Provides read-only access to private repositories in the `bowerbird-app` organization
- Allows Bundler to install private gems during the `postCreateCommand`
- Is securely injected into all Codespaces created within the organization

No additional configuration is needed when working in Codespaces.

### In Local Development

If you're developing locally and this gem depends on private Bowerbird gems, you'll need to:

1. Create a GitHub Personal Access Token with `repo` scope
2. Configure Bundler to use it:
   ```bash
   bundle config set --global GITHUB__COM your_github_token
   ```

See [LOCAL_DEVELOPMENT.md](LOCAL_DEVELOPMENT.md) and [PRIVATE_GEMS.md](PRIVATE_GEMS.md) for details.

---

## CSRF Protection

When `ENV["CODESPACES"] == "true"`:
- CSRF **origin check is relaxed** (avoids issues with GitHub's forwarded URLs).
- CSRF **authenticity tokens remain enabled** for security.

For best results, access your app consistently via:
- The Codespaces forwarded URL (`*.app.github.dev`), **or**
- `localhost:3000` (if port forwarding is set to local).

See [SECURITY.md](../SECURITY.md) for details.

---

## Running the Server

Use `bin/dev` to start both Rails and the Tailwind watcher:

```bash
cd test/dummy
bin/dev
```

This runs Foreman with `Procfile.dev`:

```
web: bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
```

Binding to `0.0.0.0` is required for Codespaces port forwarding.

---

## Port Forwarding

Codespaces automatically forwards port 3000. Find it in the **Ports** tab and click the globe icon to open in your browser.

If port 3000 is busy:

```bash
PORT=3001 bin/dev
```

---

## Rebuilding the Container

If you change `.devcontainer/` files:

1. Open the Command Palette (`Ctrl+Shift+P` / `Cmd+Shift+P`).
2. Run **Codespaces: Rebuild Container**.

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Container fails to start | Check Docker Compose logs in the terminal. |
| Database connection refused during setup | Re-run `bash .devcontainer/post-create.sh`; it defaults `DB_HOST=db` and waits for PostgreSQL before running Rails tasks. |
| Tailwind not rebuilding | Restart `bin/dev` or run `bin/rails tailwindcss:build`. |
| Port already in use | Use a different port: `PORT=3001 bin/dev`. |

---

## Files Reference

| File | Purpose |
|------|---------|
| `.devcontainer/devcontainer.json` | Codespaces/VS Code configuration |
| `.devcontainer/post-create.sh` | Robust post-create bootstrap script |
| `.devcontainer/docker-compose.yml` | Service definitions |
| `.devcontainer/Dockerfile` | Ruby container build |
| `test/dummy/Procfile.dev` | Foreman process definitions |
| `test/dummy/bin/dev` | Development startup script |

---

Happy coding in Codespaces! ☁️
