# Ecosystem dashboard

The Recording Studio ecosystem is spread across separate repositories: this core gem, the
`flat_pack` UI library, and a couple of dozen addon gems. Each one pins the others by version
requirement or git tag, so it is easy for an addon to sit quietly on an old core release long after
core has moved on.

`bin/ecosystem_audit` scans every repository in the organisation and reports which shared
dependencies are pinned behind their latest release. It writes three things from one scan:

| Output | Purpose |
| --- | --- |
| `tmp/ecosystem_audit.json` | The raw audit data, for scripting or diffing between runs |
| `tmp/ecosystem_dashboard.html` | A self-contained page that opens in any browser |
| `tmp/recording-studio-gem-updates.canvas.tsx` | A Cursor canvas that can be published as a shared team dashboard |

## Running the audit

The script talks to GitHub through the [GitHub CLI](https://cli.github.com), so authenticate first:

```bash
gh auth login
```

Then run it from the repository root:

```bash
bin/ecosystem_audit
```

A scan takes around half a minute and prints a short summary:

```
Recording Studio ecosystem — 2026-08-18
  14 of 18 active gems need updates (28 outdated pins)
  13 behind recording_studio 4.0.0
  7 behind recording_studio_accessible 0.5.0
  8 behind flat_pack 0.1.129
```

Open `tmp/ecosystem_dashboard.html` in a browser for the full picture.

### Options

| Option | Effect |
| --- | --- |
| `--json PATH` | Where to write the audit data |
| `--html PATH` | Where to write the browser dashboard |
| `--canvas PATH` | Where to write the Cursor canvas |
| `--from PATH` | Re-render the dashboards from an earlier audit instead of rescanning |
| `--quiet` | Only report errors |

`--from` is useful when you want to tweak presentation without waiting on GitHub again:

```bash
bin/ecosystem_audit --from tmp/ecosystem_audit.json
```

## Publishing the shared canvas

Cursor canvases are interactive dashboards that render beside the chat and can be published to a
URL your team can open in a browser. Cursor only picks up canvases from its own managed directory,
so copy the generated file there:

```bash
bin/ecosystem_audit --canvas ~/.cursor/projects/RecordingStudio/canvases/recording-studio-gem-updates.canvas.tsx
```

Then open it in Cursor (**Open Canvas** in the Command Palette) and choose **Publish** from the
canvas toolbar to get a shareable link. Re-running the command and publishing again refreshes the
same share with new data.

Two caveats worth knowing:

- The workspace folder name under `~/.cursor/projects/` matches how you opened the repository
  locally, so check the directory before copying into it.
- Publishing is a desktop action. Cloud agents can generate the canvas file but cannot publish it.

## How the audit decides something is outdated

The script only tracks the dependencies that the whole ecosystem shares — `recording_studio`,
`recording_studio_accessible`, and `flat_pack`. Everything else is left to Dependabot in each
repository.

For each of those it works out the newest version that provably exists, taking the higher of the
version constant on the default branch and the latest release tag. It then flags two situations:

- **A gemspec requirement that excludes the latest version.** This uses real RubyGems requirement
  matching, so `>= 0.1.0` is not flagged against 4.0.0 while `~> 3.0` and `>= 3, < 4` both are.
- **A Gemfile git tag behind the latest tag.** Development Gemfiles pin git tags, which do not
  resolve forward on their own and quietly hold a gem on old code.

When a gem pins the same dependency in both places, the two are merged into one row so the table
counts gems rather than files.

Priority reflects how much of the ecosystem a dependency blocks rather than how old the pin is:

| Priority | Dependency | Why |
| --- | --- | --- |
| High | `recording_studio` | The core engine; addons cannot adopt new capabilities without it |
| Medium | `recording_studio_accessible` | The access-control hub most addons build on |
| Low | `flat_pack` | UI only, and safe to bump independently |

Repositories that still ship the unrenamed `gem_template` scaffold are listed separately, because
they are placeholders rather than real consumers. Retired and broken repositories are skipped.

## Suggested upgrade order

The dashboard makes the shape of the work obvious, and it is usually the same shape:

1. **Unlock the hub.** Move `recording_studio_accessible` onto the current core release and cut a
   new version. Most addons depend on accessible, so until it allows the new core nothing else can
   move cleanly.
2. **Roll the addons.** Update the gems still requiring the old core, then the ones pinned below the
   new accessible release.
3. **Refresh Flat Pack tags.** These are lower risk and independent of the core migration, so they
   can land at any point.

## Keeping it honest

The audit reads the default branch of every repository, so it reflects what is committed rather
than what is released to RubyGems. Re-run it after any release to get a current picture — the
generated files live in `tmp/` and are not committed, so there is no stale copy to mistake for
fresh data.
