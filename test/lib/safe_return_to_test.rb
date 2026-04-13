# frozen_string_literal: true

require "test_helper"

class SafeReturnToTest < ActiveSupport::TestCase
  test "sanitize preserves safe local paths and nested queries" do
    sanitized = RecordingStudio::SafeReturnTo.sanitize(
      "/recordings/123?filters%5Bcopied%5D=1&filters%5Bids%5D%5B%5D=2"
    )

    assert_equal "/recordings/123?filters%5Bcopied%5D=1&filters%5Bids%5D%5B%5D=2", sanitized
  end

  test "sanitize rejects parser edge cases in paths" do
    assert_nil RecordingStudio::SafeReturnTo.sanitize("/recordings\\123")
    assert_nil RecordingStudio::SafeReturnTo.sanitize("/recordings%2F123")
    assert_nil RecordingStudio::SafeReturnTo.sanitize("/recordings;admin=1")
    assert_nil RecordingStudio::SafeReturnTo.sanitize("/recordings%0A123")
  end

  test "sanitize can restrict redirects to allowed prefixes" do
    assert_equal "/workspaces/123?copied=1",
                 RecordingStudio::SafeReturnTo.sanitize(
                   "/workspaces/123?copied=1",
                   allowed_prefixes: %w[/workspaces /recordings]
                 )
    assert_nil RecordingStudio::SafeReturnTo.sanitize(
      "/admin",
      allowed_prefixes: %w[/workspaces /recordings]
    )
  end
end
