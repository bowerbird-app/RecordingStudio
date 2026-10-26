# RecordingStudio Asset Integration Notes

RecordingStudio's current install-time asset story is intentionally small.

## What The Engine Ships Today

- no engine JavaScript entrypoint
- no engine Importmap configuration
- no Sprockets installer behavior
- Tailwind view-scanning support for host apps that already use `app/assets/tailwind/application.css`

## What The Install Generator Does

If the host app has `app/assets/tailwind/application.css`, the install generator inserts:

```css
@source "../../vendor/bundle/**/recording_studio/app/views/**/*.erb";
```

It inserts that line after an existing Tailwind import and avoids duplicate insertion. If the Tailwind entrypoint is not
present, the generator prints manual instructions instead of creating broader asset wiring.

## What The Install Generator Does Not Do

The current generator does not:

- create `app/javascript/application.js`
- modify `config/importmap.rb`
- install Stimulus controllers
- add Sprockets `require` directives
- copy a theme stylesheet into the host app

If RecordingStudio grows a bundled UI later, document those behaviors only when code exists for them.

## Dummy App Reference

The dummy app is the best current reference for asset setup.

`test/dummy/app/assets/tailwind/application.css` currently:

- imports Tailwind
- scans FlatPack component templates and helpers from Bundler paths
- re-sets the kit `--font-sans`, `--font-mono`, and `--radius-*` scale on unlayered `:root`
- scans dummy app views
- scans the engine's `app/views/**/*.erb`

Color and spacing tokens stay in `flat_pack/variables`. The layout links that
sheet, `flat_pack/application`, and `flat_pack/rich_text` before this Tailwind
file. The viewport meta includes `viewport-fit=cover`.
`app/javascript/application.js` calls `initLocalTimes`.

The development watcher is wired through `test/dummy/Procfile.dev`:

```text
web: bin/rails server -b 0.0.0.0
css: bin/rails tailwindcss:watch
```

## Maintainer Guidance

If you add engine views or components later:

- keep Tailwind scan paths explicit
- document any new install-generator behavior alongside the code change
- avoid promising JS or asset-pipeline integration that the engine does not actually implement
