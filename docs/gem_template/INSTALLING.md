# Installing RecordingStudio In A Host Application

This guide documents the current install flow for RecordingStudio as a Rails engine. For API details after installation,
use [../../README.md](../../README.md) and [../API_REFERENCE.md](../API_REFERENCE.md).

## Prerequisites

- Ruby 3.3+
- Rails 8.1+
- ActiveRecord-backed application
- TailwindCSS only if your host app wants the generator to wire engine view scanning automatically

## Standard Install Flow

1. Add the gem to your `Gemfile`.

```ruby
gem "recording_studio"
```

For local development against a checkout:

```ruby
gem "recording_studio", path: "../RecordingStudio"
```

2. Install dependencies.

```bash
bundle install
```

3. Run the install generator.

```bash
bin/rails generate recording_studio:install
```

4. Run the copied migrations.

```bash
bin/rails db:migrate
```

## What The Install Generator Actually Does

The current generator:

- mounts `RecordingStudio::Engine` at `/recording_studio`
- creates `config/initializers/recording_studio.rb`
- invokes `recording_studio:migrations`
- optionally creates `config/recording_studio.yml`
- adds Tailwind `@source` scanning for engine ERB views when `app/assets/tailwind/application.css` exists

The mounted engine is not a bundled application UI. RecordingStudio currently ships no default root page or browser
routes under `/recording_studio`, so do not treat that mount path as an installation smoke test.

## Minimal Post-Install Wiring

RecordingStudio only becomes useful after you declare and register the recordable types your app wants to store.

Initializer example:

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = %w[Workspace Page]
end
```

Model declarations:

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end
```

Actor wiring:

```ruby
class ApplicationController < ActionController::Base
  before_action :current_actor

  private

  def current_actor
    Current.actor = current_user
    Current.impersonator = nil
  end
end
```

First write:

```ruby
workspace = Workspace.create!(name: "Studio")
root = RecordingStudio.root_recording_for(workspace)

root.record(Page) do |page|
  page.title = "Getting started"
end
```

## `config.recordable_types` Versus `register_recordable_type`

Most host apps should set `config.recordable_types` during boot. Use `RecordingStudio.register_recordable_type(...)`
when an addon or runtime integration needs incremental registration after boot. Calling both is usually unnecessary,
but harmless if they describe the same types.

## Tailwind Integration

If the host app has `app/assets/tailwind/application.css`, the generator inserts:

```css
@source "../../vendor/bundle/**/recording_studio/app/views/**/*.erb";
```

That is the only asset integration RecordingStudio currently performs. The engine does not ship install-time JS,
Importmap, or Sprockets wiring.

## Verification

Good validation checks after installation:

```ruby
RecordingStudio.validate_recordable_declarations!
RecordingStudio.root_recordable_types
RecordingStudio.root_recording_for(Workspace.first)
```

Or from a console/session:

```ruby
root = RecordingStudio.root_recording_for(Workspace.first)
root.recordings_query
```

## Troubleshooting

| Issue | What to check |
| --- | --- |
| `RecordingStudio::MissingRecordableDeclaration` | Add `recording_studio_recordable(...)` to every configured ActiveRecord type, or temporarily set `require_recordable_declarations = false` while migrating. |
| `RecordingStudio::RootNotAllowed` | You called `root_recording_for` for a type that does not declare `root: true`. |
| `RecordingStudio::InvalidParent` | The child type needs a valid `parent_recording:` and an allowed parent type. |
| Tailwind classes from engine views are missing | Rebuild CSS with `bin/rails tailwindcss:build` and verify the `@source` line exists. |
| `/recording_studio` returns 404 | Expected unless your app or a future engine version adds routes there. |

## Related Docs

- [CONFIGURATION.md](CONFIGURATION.md)
- [MIGRATIONS.md](MIGRATIONS.md)
- [../API_REFERENCE.md](../API_REFERENCE.md)
