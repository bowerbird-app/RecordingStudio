> **Architecture Documentation**
> *   **Canonical Source:** [bowerbird-app/gem_template](https://github.com/bowerbird-app/gem_template/tree/main/docs/gem_template)
> *   **Last Updated:** December 12, 2025
>
> *Maintainers: Please update the date above when modifying this file.*

---

# Private Gem Dependencies

This gem template may depend on private Ruby gems hosted as GitHub repositories under the `bowerbird-app` organization. This document explains how authentication works across different environments.

---

## Overview

Private gems are referenced in the `Gemfile` using Git URLs:

```ruby
gem 'mothball', git: 'https://github.com/bowerbird-app/mothball.git'
```

To install these gems, Bundler needs authentication to access private GitHub repositories.

---

## GitHub Codespaces

**No configuration required.** 

The organization-level Codespaces secret `BOWERBIRD_ORG_CODESPACE_TOKEN` is automatically available in all Codespaces. This token:

- Is configured at the `bowerbird-app` organization level
- Has read access to all private repositories in the organization
- Is automatically used by Bundler during `bundle install`

The `postCreateCommand` in `.devcontainer/devcontainer.json` handles gem installation automatically.

---

## Local Development

To work with private gems locally, you need a GitHub Personal Access Token:

### 1. Create a Personal Access Token

1. Go to [GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens)
2. Click **Generate new token (classic)**
3. Give it a descriptive name (e.g., "Bundler - Bowerbird Gems")
4. Select the **`repo`** scope (full control of private repositories)
5. Click **Generate token**
6. Copy the token immediately (you won't see it again)

### 2. Configure Bundler

Set the token globally:

```bash
bundle config set --global GITHUB__COM your_github_token_here
```

Or set it per-project:

```bash
bundle config set --local GITHUB__COM your_github_token_here
```

### 3. Verify

Run `bundle install` – it should successfully fetch private gems.

---

## Production Deployment

Production applications using this gem template will need access to private dependencies.

### Requirements

- **GitHub Personal Access Token** with `repo` scope
- **Organization membership** – the token owner must have access to `bowerbird-app` private repositories

### Configuration

Set the token as an environment variable or configure it in your deployment system:

**Option 1: Environment variable**

```bash
export BUNDLE_GITHUB__COM=your_production_token
```

**Option 2: Bundler config**

```bash
bundle config set --local GITHUB__COM your_production_token
```

**Option 3: Git credentials helper** (for Docker builds)

In your `Dockerfile`:

```dockerfile
ARG GITHUB_TOKEN
RUN git config --global url."https://oauth2:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
RUN bundle install
```

Then pass the token during build:

```bash
docker build --build-arg GITHUB_TOKEN=$GITHUB_TOKEN .
```

---

## Security Best Practices

- **Never commit tokens** to version control
- Use **environment-specific tokens** (dev, staging, prod)
- Rotate tokens periodically
- Use **read-only tokens** where possible (`:repo` scope is required for private gems)
- Store tokens in secrets managers (GitHub Secrets, AWS Secrets Manager, etc.)

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `bundle install` fails with 401/403 | Check token has `repo` scope and org access |
| "Repository not found" | Ensure token owner is a member of `bowerbird-app` |
| Token not being used | Verify `bundle config get GITHUB__COM` shows your token |
| Works locally but fails in CI | Set `BUNDLE_GITHUB__COM` in CI environment variables |

---

## Reference

- [Bundler Git Authentication](https://bundler.io/man/bundle-config.1.html#CREDENTIALS-FOR-GEM-SOURCES)
- [GitHub Personal Access Tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
- [Codespaces Secrets](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-secrets-for-your-codespaces)

---

Need help? Check the internal Bowerbird docs or ask in `#engineering`.
