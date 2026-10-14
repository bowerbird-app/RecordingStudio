# Addon boilerplate building blocks

Recording Studio addon gems historically copied the same small scaffolding:
configuration shells, hook registries, service bases, migrations install
generators, and API admin-root access helpers. Core now owns those building
blocks so addon PRs can inherit instead of paste.

This guide is for addon authors. Host apps that only use RecordingStudio do not
need these classes.

## What To Use

| Building block | Core API | Replaces sibling copies of |
| --- | --- | --- |
| Hook registry | `RecordingStudio::Hooks` | Per-gem `lib/<gem>/hooks.rb` full registries |
| Addon configuration | `RecordingStudio::AddonConfiguration` | Shared `hooks` / `merge!` / `to_h` shell in addon `configuration.rb` |
| Service objects | `RecordingStudio::Services::BaseService` | Byte-identical `services/base_service.rb` copies |
| Addon-scoped service hooks | `RecordingStudio::Services::AddonBaseService` | Thin publishable-style subclasses that retarget hooks |
| Migrations install generator | `RecordingStudio::Generators::MigrationsGeneratorBase` | Template-style `migrations_generator.rb` copies |
| API admin-root access | `RecordingStudio::Api::Access` / `Access::WithSiteAdmin` | Per-gem `api/access.rb` modules |

Core's own `RecordingStudio::Configuration` and
`RecordingStudio::Generators::MigrationsGenerator` stay separate. They keep
core-specific settings (`recordable_types`, capabilities, `--full_history`).

## Hooks

Prefer a core `Hooks` instance on the addon configuration:

```ruby
class Configuration < RecordingStudio::AddonConfiguration
  # @hooks is already RecordingStudio::Hooks.new
end
```

Do not ship a second full `Hooks` class in the addon unless you still need a
temporary `SomeGem::Hooks.run` facade during migration. The instance API on
`RecordingStudio::Hooks` is the shared implementation (including
`before_record` / `after_record` / `registered_counts`).

## Configuration

```ruby
module RecordingStudioMessages
  class Configuration < RecordingStudio::AddonConfiguration
    attr_accessor :public_contact_sent_icon

    def initialize
      super
      @public_contact_sent_icon = "rocket-launch"
    end

    def to_h
      {
        public_contact_sent_icon: public_contact_sent_icon,
        hooks_registered: hooks_registered
      }
    end
  end
end
```

Keep gem-specific attributes and custom setters in the subclass. Override
`merge!` only when the gem intentionally restricts keys (Accessible) or special
cases a setter (Trashable). AI's validate-heavy configuration is not a fit for
this base.

## Services

Host or addon commands that should use core hooks:

```ruby
class PublishPage < RecordingStudio::Services::BaseService
  # fires RecordingStudio.configuration.hooks
end
```

Addon commands that must keep a separate addon hook registry:

```ruby
module RecordingStudioPublishable
  module Services
    class BaseService < ::RecordingStudio::Services::AddonBaseService
      self.hooks_owner = RecordingStudioPublishable
    end
  end
end
```

`failure(error, errors: [], value: nil)` accepts an optional failure `value` so
Accessible-style call sites can inherit without behavior change.

## Migrations generator

```ruby
module GemTemplate
  module Generators
    class MigrationsGenerator < RecordingStudio::Generators::MigrationsGeneratorBase
      source_root File.expand_path("../../../..", __dir__)
      self.engine_label = "GemTemplate"
      desc "Copy GemTemplate migrations to your application"
    end
  end
end
```

Override `migrations_directory`, `copy_migrations`, `migration_exists?`, or
`next_migration_number` when a gem diverges (Accessible filters, Embeddable
timestamp strategy, core `--full_history`).

## API access

```ruby
# access_recording_resolver only (messages, Oauth, trashable)
module RecordingStudioMessages
  module Api
    Access = RecordingStudio::Api::Access
  end
end

# prefer site_admin_recording_resolver and rescue errors
# (AI, notifications, presskits, terms_and_conditions)
module RecordingStudioAI
  module Api
    Access = RecordingStudio::Api::Access::WithSiteAdmin
  end
end
```

Support keeps its heavier helpers and can call
`RecordingStudio::Api::Access.resolve_admin_root_recording(...)` for the two
resolver policies it already uses.

## Files

- `lib/recording_studio/hooks.rb`
- `lib/recording_studio/addon_configuration.rb`
- `lib/recording_studio/services/base_service.rb`
- `lib/recording_studio/services/addon_base_service.rb`
- `lib/recording_studio/generators/migrations_generator_base.rb`
- `lib/recording_studio/api/access.rb`
