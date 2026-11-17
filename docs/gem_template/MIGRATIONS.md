# RecordingStudio Migrations

RecordingStudio ships two migration sets and a generator that chooses between them.

## Which Generator To Use

Fresh installs:

```bash
bin/rails generate recording_studio:migrations
```

Upgrade paths that need the full historical chain:

```bash
bin/rails generate recording_studio:migrations --full_history
```

Then apply the copied migrations:

```bash
bin/rails db:migrate
```

## Migration Sources

RecordingStudio keeps migrations in two directories:

- `db/install_migrate/`: the clean schema for brand-new host apps
- `db/migrate/`: the full historical chain, including compatibility and cleanup migrations for older installations

The default generator copies from `db/install_migrate/` because fresh installs should not replay legacy table renames,
container-to-root conversions, or extracted access-control/device-session cleanup steps.

## Generator Options

Generator-specific options:

| Option | Default | Meaning |
| --- | --- | --- |
| `--skip-existing` | `true` | Skip migrations whose names already exist in the host app, ignoring timestamps. |
| `--full_history` | `false` | Copy from `db/migrate/` instead of `db/install_migrate/`. |

Standard Rails generator flags such as `--pretend` still work, but the options above are the RecordingStudio-specific
behavior controls.

## Fresh Install Versus Upgrade Guidance

Use the default install set when:

- the host app has never installed RecordingStudio before
- you want the current schema without replaying historical compatibility steps

Use `--full_history` only when:

- the host app previously depended on RecordingStudio's historical migration chain
- you are aligning an older installation with newer core releases and need the upgrade-only migrations too

## Current Schema Direction

The current fresh-install schema models:

- `recording_studio_recordings`
- `recording_studio_events`, including required `root_recording_id` and an index on `(occurred_at, created_at, id)`, newest first, for cross-root recent events
- `recording_studio_recordings` index `index_rs_recordings_on_root_type_created_at_id` on `(root_recording_id, recordable_type, created_at, id)`, newest first, with no `WHERE` clause, for a root plus type page. `index_rs_recordings_on_root_and_recordable` remains for `recordable_id` lookups under a root
- `recording_studio_recordings.root_recording_id` is `NOT NULL`. From 7.5.0 it is DB-enforced: every child's root equals its parent's root; parentless rows are their own root. Readers may trust it. The unique index is `index_rs_recordings_on_id_and_root` on `(id, root_recording_id)`. `fk_rs_recordings_on_parent_and_root` references that pair and is `DEFERRABLE INITIALLY DEFERRED`. `chk_rs_recordings_parentless_own_root` requires `parent_recording_id IS NOT NULL OR root_recording_id = id`. There is no trigger.

Historical tables and columns related to access control, device sessions, and older container naming are not part of the
fresh-install path anymore.

## Adding New Engine Migrations

When maintainers add migrations to the engine:

- add the migration to both `db/install_migrate/` and `db/migrate/` when new installs and upgrades both need it
- add the migration only to `db/migrate/` when it exists purely to transform or remove legacy state during upgrades

Keep table names namespaced with the `recording_studio_` prefix.

## How The Generator Copies Files

The generator:

- scans the selected source directory
- compares migration names without timestamps
- copies each missing migration into the host app's `db/migrate/`
- assigns a fresh timestamp in the host app

That means host-app migration version numbers will differ from the engine's version numbers even when the migration body
is the same.

## Testing Migrations In This Repo

The dummy app is the easiest validation target:

```bash
cd test/dummy
bin/rails db:migrate
bin/rails db:rollback
```

Generator-specific tests also live in the top-level test suite.

## Troubleshooting

| Issue | What to check |
| --- | --- |
| A migration was not copied | The same migration name may already exist in the host app. Re-run with `--no-skip-existing` only if you really need another copy. |
| Fresh install pulls legacy cleanup migrations | Use the default generator without `--full_history`. |
| Upgrading app still misses compatibility steps | Re-run with `--full_history` and compare the host app's existing migration names against `db/migrate/`. |
| Migration versions differ from the engine | Expected; the generator gives host apps fresh timestamps. |

## Files To Check

- `lib/generators/recording_studio/migrations/migrations_generator.rb`
- `db/install_migrate/`
- `db/migrate/`
