# Git-Sourced Dependencies And Repository Access

RecordingStudio currently depends on git-sourced repositories in development, most notably `flat_pack` from the
`bowerbird-app` organization. This document explains what to check when Bundler or GitHub access fails.

## Current Git-Sourced Dependencies

At the time of writing:

- the top-level `Gemfile` references `flat_pack` via `https://github.com/bowerbird-app/flatpack.git`
- the dummy app `Gemfile` also references `flat_pack`
- the devcontainer requests read access to `bowerbird-app/gem_docs` for shared documentation material

If those repositories are public in your environment, no extra configuration is required. If any of them are private,
Git must be able to authenticate to GitHub before `bundle install` will succeed.

## Quick Verification

Before debugging Bundler, make sure GitHub access works directly:

```bash
git ls-remote https://github.com/bowerbird-app/flatpack.git
```

If that command fails with authentication or repository access errors, fix GitHub access first.

## Local Development Options

Any approach that makes Git able to clone the dependency is fine. Common options:

- authenticate with the GitHub CLI and credential manager
- use your OS keychain-backed Git credential helper
- use a personal access token in a Git URL rewrite

Example URL rewrite:

```bash
git config --global url."https://oauth2:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
```

That is usually more reliable for git-sourced gems than configuring only `BUNDLE_GITHUB__COM`, because the dependency is
cloned by Git over HTTPS.

## Codespaces And Devcontainers

Codespaces usually inherit repository access from the signed-in GitHub account plus any organization or repository
permissions granted to the codespace. If `bundle install` fails inside the devcontainer, verify that the account running
the codespace can read the dependency repository.

## CI Or Docker Builds

For automated builds, configure Git before running Bundler:

```dockerfile
ARG GITHUB_TOKEN
RUN git config --global url."https://oauth2:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
RUN bundle install
```

Use a read-only token with access only to the repositories you need.

## Troubleshooting

| Issue | What to check |
| --- | --- |
| `bundle install` fails with 401 or 403 | The GitHub token or signed-in account cannot read the git-sourced dependency. |
| `Repository not found` | The repo may be private, renamed, or unavailable to the current GitHub identity. |
| Bundler works locally but not in Codespaces | The local machine may have cached Git credentials that the container does not. |
| `BUNDLE_GITHUB__COM` is set but clones still fail | Git-sourced gems may still require Git credential configuration, not just Bundler source credentials. |

## Files To Check

- `Gemfile`
- `test/dummy/Gemfile`
- `.devcontainer/devcontainer.json`
