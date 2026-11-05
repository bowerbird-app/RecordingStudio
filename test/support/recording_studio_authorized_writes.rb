# frozen_string_literal: true

module RecordingStudioAuthorizedWrites
  TEST_ACTOR_EMAIL = "recording-studio-test-actor@example.com"

  module_function

  def install!
    RecordingStudio.configuration.authorize_write = ->(actor:, **) { actor.present? }
    RecordingStudio.configuration.actor = method(:actor)
  end

  def actor
    current = defined?(Current) && Current.respond_to?(:actor) ? Current.actor : nil
    return current if current.present?

    find_or_create_test_actor
  end

  def find_or_create_test_actor
    return unless defined?(User)

    User.find_by(email: TEST_ACTOR_EMAIL) || User.create!(
      name: "Test Actor",
      email: TEST_ACTOR_EMAIL,
      password: "password123",
      password_confirmation: "password123"
    )
  end
end
