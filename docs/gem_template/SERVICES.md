# RecordingStudio Service Objects

RecordingStudio ships a small service-object base class for maintainers and addon authors who want a consistent
command-style API with hook support.

## What Exists Today

- `RecordingStudio::Services::BaseService`

Use `BaseService` for addon or host-app command objects. RecordingStudio core writes go through
`RecordingStudio.record!` rather than a bundled example service.

## Call Pattern

```ruby
module RecordingStudio
  module Services
    class PublishPage < BaseService
      def initialize(page_recording:)
        @page_recording = page_recording
      end

      private

      def perform
        return failure("recording is required") unless @page_recording

        @page_recording.log_event!(action: "published")
        success(@page_recording)
      end

      def service_args
        { recording_id: @page_recording&.id }
      end
    end
  end
end

result = RecordingStudio::Services::PublishPage.call(page_recording: page_recording)
result.success?
result.value
```

Returned results respond to:

- `success?`
- `failure?`
- `value`
- `error`
- `errors`
- `on_success { |value| ... }`
- `on_failure { |error, errors| ... }`
- `value!`

## Hook Integration

`BaseService` automatically cooperates with `RecordingStudio.configuration.hooks`.

Relevant hooks:

- `before_service`
- `after_service`
- `around_service`

`RecordingStudio.record!` and `RecordingStudio.record_events!` also fire write-path hooks:

- `before_record`
- `after_record`

Example:

```ruby
RecordingStudio.configuration.hooks.before_service do |service_class, args|
  Rails.logger.info("Starting #{service_class} with #{args.inspect}")
end

RecordingStudio.configuration.hooks.before_record do |payload|
  Rails.logger.info("RecordingStudio write: #{payload[:action]}")
end
```

Override `service_args` in a service subclass when you want hook callbacks to receive meaningful metadata.

## Hide secrets from hooks

`before_service` receives the service class and `service_args`. `after_service` receives the service class and the result. `around_service` receives the service and a block that runs the service. That is the default, and callers receive that same result.

Override `hook_result` when the result carries a secret. Hooks then see the object you return. `call` still returns the real result to the caller and to the block passed to `call`.

```ruby
def hook_result(result)
  success("[redacted]")
end
```

`after_service` receives `hook_result` of the result `call` will return. The block given to `around_service` runs `perform`, then returns `hook_result` of that result. If the around hook returns that same object, `call` uses the real result. If the around hook returns any other object, `call` uses the hook's object. That replacement matches 7.0.0.

Override `hook_subject` when the service object itself carries a secret. `around_service` receives that object instead of the service. Global listeners filter by calling `is_a?` or `kind_of?` with the service class, so the object has to answer both truthfully for the real service class.

```ruby
def hook_subject
  PublicView.new(self)
end
```

Leave both methods at their defaults and every hook sees the same objects it sees today.
