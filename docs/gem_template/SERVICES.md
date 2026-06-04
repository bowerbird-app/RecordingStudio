# RecordingStudio Service Objects

RecordingStudio ships a small service-object base class for maintainers and addon authors who want a consistent
command-style API with hook support.

## What Exists Today

- `RecordingStudio::Services::BaseService`
- `RecordingStudio::Services::ExampleService`

The example service is intentionally trivial. The reusable part is `BaseService`.

## Call Pattern

```ruby
result = RecordingStudio::Services::ExampleService.call(name: "World")

result.success? # => true
result.value    # => "Hello, World!"
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

## Implementing A Service

Subclass `BaseService`, implement `perform`, and return `success(...)` or `failure(...)`.

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
```

## Hook Integration

`BaseService` automatically cooperates with `RecordingStudio.configuration.hooks`.

Relevant hooks:

- `before_service`
- `after_service`
- `around_service`

Example:

```ruby
RecordingStudio.configuration.hooks.before_service do |service_class, args|
  Rails.logger.info("Starting #{service_class} with #{args.inspect}")
end
```

Override `service_args` in a service subclass when you want hook callbacks to receive meaningful metadata.
