# RecordingStudio Security Notes

RecordingStudio is a data and history engine. It is intentionally narrow in scope: core manages recordings,
recordables, and events, while authorization and root-selection policy belong to the host app or addon gems.

## Core Security Boundaries

- RecordingStudio does not ship built-in access control, role checks, or device-session persistence.
- Capability-owned child recordables only grant structural parent eligibility; they do not bypass addon-level
  authorization or validation.
- `RecordingStudio::ApplicationController` uses `protect_from_forgery with: :exception`.
- Event actors and impersonators are polymorphic persisted records. The host app is responsible for assigning
  `Current.actor` and `Current.impersonator` or passing `actor:` and `impersonator:` explicitly.

## Dummy App Development Posture

The dummy app demonstrates one acceptable development posture:

- Devise protects normal pages with `before_action :authenticate_user!`
- `ApplicationController` sets `Current.actor = current_user` and clears `Current.impersonator`
- development keeps CSRF tokens enabled but sets `config.action_controller.forgery_protection_origin_check = false`
  so localhost and forwarded Codespaces URLs work together

That origin-check relaxation is for development convenience only.

## Secrets And Credentials

- dummy app Rails credentials keys are gitignored
- database credentials are driven by environment variables
- git-sourced dependencies may require separate GitHub credentials; see [PRIVATE_GEMS.md](PRIVATE_GEMS.md)

## Supply Chain Notes

- the gemspec requires RubyGems MFA for publishing
- container services use official Postgres, Redis, and Ruby base images for development
- the repository currently has a git-sourced development dependency on `flat_pack`

## Production Checklist For Host Apps

If a host app uses RecordingStudio in production, review at least the following:

1. Authentication and authorization around every read and write path
2. Actor provenance for background jobs, system actors, and impersonation flows
3. CSRF, session, and host-header settings in the host app
4. Retention and auditing requirements for append-only event history
5. Secret handling for databases, Redis, and any git-sourced dependencies
6. Rate limiting and abuse controls for endpoints that create events or revisions

## Reporting

For security-sensitive issues, prefer a private report or contact the maintainers at `opensource@bowerbird.app`.
