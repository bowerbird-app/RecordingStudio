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

`RecordingStudio.record!` also fires write-path hooks:

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
