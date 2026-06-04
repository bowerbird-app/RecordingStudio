# RecordingStudio Configuration

This guide documents the current `RecordingStudio::Configuration` object and the files that feed it. Runtime method
selection lives in [../API_REFERENCE.md](../API_REFERENCE.md); this file focuses on boot-time setup.

## Configuration Sources And Precedence

RecordingStudio loads configuration in this order, with later sources winning:

1. Defaults from `RecordingStudio::Configuration#initialize`
2. `config/recording_studio.yml` via `Rails.application.config_for(:recording_studio)` when present
3. `config.x.recording_studio` when present
4. `config/initializers/recording_studio.rb`

Use the Ruby initializer for anything dynamic or callable. YAML is best for simple serializable values.

## Core Settings

| Setting | Type | Default | Notes |
| --- | --- | --- | --- |
| `recordable_types` | `Array<String>` | `[]` | Recordable classes available to delegated type resolution. |
| `require_recordable_declarations` | `true` or `false` | `true` | When `true`, configured ActiveRecord types must call `recording_studio_recordable(...)`. |
| `actor` | callable | `-> { Current.actor }` when `Current` exists | Used when write APIs omit `actor:`. |
| `impersonator` | callable | `-> { Current.impersonator }` when `Current` exists | Used when write APIs omit `impersonator:`. |
| `event_notifications_enabled` | boolean | `true` | Controls `recordings.event_created` notifications. |
| `instrumentation_enabled` | boolean alias | same as `event_notifications_enabled` | Compatibility alias for the notification switch. |
| `idempotency_mode` | `:return_existing` or `:raise` | `:return_existing` | Controls duplicate `idempotency_key` behavior. |
| `recordable_dup_strategy` | symbol or callable | `:dup` | Global duplication strategy used by `revise`. |
| `recordable_dup_strategies` | `Hash<String, callable>` | `{}` | Per-type overrides registered with `register_recordable_dup_strategy`. |
| `hooks` | `RecordingStudio::Hooks` | new hook registry | Shared lifecycle and service hook registry. |

## Typical Initializer

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = %w[Workspace Page]
  config.require_recordable_declarations = true
  config.actor = -> { Current.actor }
  config.impersonator = -> { Current.impersonator }
  config.event_notifications_enabled = true
  config.idempotency_mode = :return_existing
  config.recordable_dup_strategy = :dup

  config.register_recordable_dup_strategy("Page") do |recordable|
    Page.new(title: recordable.title)
  end
end
```

## YAML Example

Only put static values in YAML. Callables and custom duplication blocks belong in the initializer.

```yaml
development:
  recordable_types:
    - Workspace
    - Page
  instrumentation_enabled: true
  idempotency_mode: return_existing
  recordable_dup_strategy: dup

production:
  recordable_types: []
  instrumentation_enabled: true
  idempotency_mode: return_existing
  recordable_dup_strategy: dup
```

## `config.x.recording_studio`

If your app prefers Rails configuration namespaces, RecordingStudio also reads `config.x.recording_studio`:

```ruby
config.x.recording_studio.recordable_types = %w[Workspace Page]
config.x.recording_studio.idempotency_mode = :return_existing
```

## Capability State In Configuration

The configuration object stores capability enablement and per-type capability options.

Useful methods:

- `enable_capability(capability, on:)`
- `capability_enabled?(capability, for_type:)`
- `capabilities_for(type)`
- `set_capability_options(capability, on:, **options)`
- `capability_options(capability, for_type:)`

In application code, prefer the top-level `RecordingStudio.enable_capability(...)` and related helpers unless you are
already working directly with the configuration object.

## Hooks

`RecordingStudio.configuration.hooks` exposes the shared hook registry used by services and engine lifecycle events.

Examples:

```ruby
RecordingStudio.configuration.hooks.before_service do |service_class, args|
  Rails.logger.info("Starting #{service_class} with #{args.inspect}")
end

RecordingStudio.configuration.hooks.after_initialize do
  Rails.logger.info("RecordingStudio loaded")
end
```

## Removed Configuration Keys

The configuration object intentionally ignores removed keys such as `features` and warns instead. Access-control and
device-session behavior were extracted from core and should now live in the host app or an addon gem.

## Troubleshooting

| Issue | What to check |
| --- | --- |
| `config/recording_studio.yml` seems ignored | Ensure the file is valid YAML and uses Rails environment keys such as `development:` or `production:`. |
| Missing declaration errors on boot | Set `recordable_types` only for types that actually call `recording_studio_recordable(...)`, or temporarily disable strict enforcement during upgrades. |
| Callable settings do not work from YAML | Move `actor`, `impersonator`, or custom duplication logic into the Ruby initializer. |
| Old access/device-session config no longer works | Move that configuration to the extracted addon or host app; core no longer honors it. |

## Files To Check

- `lib/recording_studio/configuration.rb`
- `lib/recording_studio/engine.rb`
- `lib/generators/recording_studio/install/templates/recording_studio_initializer.rb`
- `lib/generators/recording_studio/install/templates/recording_studio.yml`
