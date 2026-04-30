# RecordingStudio Dummy App

This Rails app exercises the local `recording_studio` checkout and the pinned FlatPack UI integration used for sandbox and integration coverage.

## Dependencies

- `recording_studio` is loaded from the repository root via `path: "../.."`.
- `flat_pack` is pinned to `v0.1.33` from `https://github.com/bowerbird-app/flatpack.git`.

## Setup

```bash
bundle install
bin/rails db:setup
bin/rake flat_pack:verify_install
```

## Development

```bash
bin/dev
```

This starts the Rails server and Tailwind watcher defined in `Procfile.dev`.

## Tests

```bash
bundle exec rake test
```

Run the FlatPack verifier after dependency or asset-wiring changes so importmap, Stimulus, layout, and Tailwind contract drift fails fast.
