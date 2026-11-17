# frozen_string_literal: true

require "test_helper"

class DenialTest < Minitest::Test
  class SampleError < StandardError
    include RecordingStudio::Denial

    def initialize(message = "Not allowed", code:, details: nil)
      super(message)
      denial(code: code, details: details)
    end
  end

  def setup
    @gate_overrides = RecordingStudio.configuration.gate_overrides
    RecordingStudio::Gates.reset!
  end

  def teardown
    RecordingStudio::Gates.reset!
    RecordingStudio.configuration.gate_overrides = @gate_overrides
  end

  def test_allow_and_deny_default_code_and_details_to_nil
    allow = RecordingStudio::GateDecision.allow
    deny = RecordingStudio::GateDecision.deny(redirect_to: "/stay", reason: "limit")

    assert_nil allow.code
    assert_nil allow.details
    assert_nil deny.code
    assert_nil deny.details

    RecordingStudio.register_gate("recording_studio.export", "open") { true }
    ran = RecordingStudio.check_gate("recording_studio.export", actor: :ada)

    assert_predicate ran, :allowed?
    assert_nil ran.code
    assert_nil ran.details
  end

  def test_string_code_is_stored_as_a_symbol
    decision = RecordingStudio::GateDecision.deny(code: "not_allowed")
    error = SampleError.new(code: "not_allowed")

    assert_equal :not_allowed, decision.code
    assert_equal :not_allowed, error.code
    assert_nil decision.details
  end

  def test_invalid_code_and_details_raise
    [1, true, false, [], {}, Object.new].each do |bad_code|
      assert_raises(ArgumentError) { RecordingStudio::GateDecision.deny(code: bad_code) }
      assert_raises(ArgumentError) { SampleError.new(code: bad_code) }
    end

    bad_details = [
      "nope",
      [{ ok: true }],
      { count: Object.new },
      { count: Float::NAN },
      { count: Float::INFINITY },
      { 1 => "nope" },
      { "limit" => 1, limit: 2 },
      { items: [{ name: Object.new }] }
    ]
    bad_details.each do |details|
      assert_raises(ArgumentError) { RecordingStudio::GateDecision.deny(details: details) }
      assert_raises(ArgumentError) { SampleError.new(code: :not_allowed, details: details) }
    end
  end

  def test_details_are_deep_frozen_and_ignore_later_changes
    label = +"ada"
    raw = {
      "name" => label,
      flag: :on,
      count: 2,
      ratio: 1.5,
      yes: true,
      no: false,
      note: nil,
      items: [+"a", { "n" => 1 }],
      nested: { "ok" => true }
    }
    decision = RecordingStudio::GateDecision.deny(code: :not_allowed, details: raw)
    label << " changed"
    raw[:nested]["extra"] = false
    raw[:items][0] << "b"
    raw[:items][1]["n"] = 9
    expected = {
      name: "ada",
      flag: :on,
      count: 2,
      ratio: 1.5,
      yes: true,
      no: false,
      note: nil,
      items: ["a", { n: 1 }],
      nested: { ok: true }
    }

    assert_equal expected, decision.details
    assert_predicate decision, :frozen?
    assert_predicate decision.details, :frozen?
    assert_predicate decision.details[:name], :frozen?
    assert_predicate decision.details[:items], :frozen?
    assert_predicate decision.details[:items][0], :frozen?
    assert_predicate decision.details[:items][1], :frozen?
    assert_predicate decision.details[:nested], :frozen?
    assert_equal false, raw.frozen?
    assert_raises(FrozenError) { decision.details[:name] << "x" }
    assert_raises(FrozenError) { decision.details[:items] << "z" }
    assert_raises(FrozenError) { decision.details[:nested][:more] = 1 }
  end

  def test_decisions_compare_by_code_and_details
    left = RecordingStudio::GateDecision.deny(
      code: :not_allowed,
      details: { "limit" => 3, nested: { "ok" => true } },
      reason: "limit"
    )
    right = RecordingStudio::GateDecision.deny(
      code: "not_allowed",
      details: { limit: 3, "nested" => { ok: true } },
      reason: "limit"
    )
    other = RecordingStudio::GateDecision.deny(
      code: :other,
      details: { limit: 3, nested: { ok: true } },
      reason: "limit"
    )
    empty = RecordingStudio::GateDecision.deny(code: :not_allowed, details: {}, reason: "limit")
    blank = RecordingStudio::GateDecision.deny(code: :not_allowed, reason: "limit")

    assert_equal left, right
    assert left.eql?(right)
    assert_equal left.hash, right.hash
    assert_equal :stored, { left => :stored }[right]
    assert_equal false, left == other
    assert_nil({ left => :stored }[other])
    assert_equal false, blank == empty
    assert_nil blank.details
    assert_equal({}, empty.details)
    assert_equal false, left == RecordingStudio::GateDecision.allow
  end

  def test_check_gate_copies_code_and_details_from_the_first_deny
    label = +"3"
    raw = { "limit" => label, nested: { "ok" => true } }
    called = []
    RecordingStudio.register_gate("recording_studio.export", "limit", priority: 1) do
      called << "limit"
      RecordingStudio::GateDecision.deny(
        redirect_to: "/stay",
        reason: "limit",
        gate: "other.gate",
        check: "other",
        code: "not_allowed",
        details: raw
      )
    end
    RecordingStudio.register_gate("recording_studio.export", "later", priority: 2) do
      called << "later"
      false
    end

    decision = RecordingStudio.check_gate("recording_studio.export", actor: :ada)
    label << "9"
    raw["extra"] = 1

    assert_equal ["limit"], called
    assert_predicate decision, :denied?
    assert_equal "/stay", decision.redirect_to
    assert_equal "limit", decision.reason
    assert_equal "recording_studio.export", decision.gate
    assert_equal "limit", decision.check
    assert_equal :not_allowed, decision.code
    assert_equal({ limit: "3", nested: { ok: true } }, decision.details)
    assert_predicate decision.details, :frozen?
    assert_predicate decision.details[:limit], :frozen?
  end

  def test_false_and_raised_checks_omit_code_and_details
    refused = check_only("member") { false }
    failed = check_only("boom") { raise "nope" }

    assert_nil refused.code
    assert_nil refused.details
    assert_equal "member", refused.check
    assert_nil failed.code
    assert_nil failed.details
    assert_equal "boom", failed.check
  end

  def test_sample_error_includes_denial
    label = +"3"
    error = SampleError.new(code: "not_allowed", details: { "limit" => label, items: [+"a"] })
    label << "9"

    assert_kind_of RecordingStudio::Denial, error
    assert_kind_of StandardError, error
    assert_equal "Not allowed", error.message
    assert_equal :not_allowed, error.code
    assert_equal({ limit: "3", items: ["a"] }, error.details)
    assert_predicate error.details, :frozen?
    assert_predicate error.details[:limit], :frozen?
    assert_predicate error.details[:items][0], :frozen?
    assert_raises(FrozenError) { error.details[:limit] << "x" }

    empty = SampleError.new(code: :not_allowed)

    assert_equal({}, empty.details)
    assert_predicate empty.details, :frozen?
    assert_same RecordingStudio::Denial::EMPTY_DETAILS, empty.details

    stripe_like = Class.new(StandardError) do
      def code
        "card_declined"
      end
    end.new("nope")

    assert_respond_to stripe_like, :code
    assert_equal "card_declined", stripe_like.code
    assert_equal false, stripe_like.is_a?(RecordingStudio::Denial)
  end

  private

  def check_only(check_name, &)
    RecordingStudio::Gates.reset!
    RecordingStudio.register_gate("recording_studio.export", check_name, &)
    RecordingStudio.check_gate("recording_studio.export", actor: :ada)
  end
end
