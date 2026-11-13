# frozen_string_literal: true

require "test_helper"
require "logger"
require "stringio"

class GatesTest < Minitest::Test
  def setup
    @gate_overrides = RecordingStudio.configuration.gate_overrides
    RecordingStudio::Gates.reset!
    RecordingStudio.configuration.gate_overrides = {}
  end

  def teardown
    RecordingStudio::Gates.reset!
    RecordingStudio.configuration.gate_overrides = @gate_overrides
    Rails.logger = @previous_logger if defined?(@previous_logger) && @previous_logger
  end

  def test_check_gate_allows_when_no_checks_are_registered
    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :allowed?
    assert_equal false, decision.denied?
    assert_nil decision.redirect_to
    assert_nil decision.reason
    assert_nil decision.gate
    assert_nil decision.check
    assert_equal false, RecordingStudio.gate_registered?("downloadable.stats")
  end

  def test_check_gate_allows_only_when_every_check_allows
    RecordingStudio.register_gate("downloadable.stats", "member") { true }
    RecordingStudio.register_gate("downloadable.stats", "quota") { true }

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :allowed?
    assert_nil decision.gate
    assert_nil decision.check
  end

  def test_first_deny_wins_and_keeps_its_redirect_and_reason
    called = []
    RecordingStudio.register_gate("downloadable.stats", "paywall", priority: 10) do
      called << "paywall"
      RecordingStudio::GateDecision.deny(redirect_to: "/upgrade", reason: "paywall")
    end
    RecordingStudio.register_gate("downloadable.stats", "quota", priority: 20) do
      called << "quota"
      RecordingStudio::GateDecision.deny(redirect_to: "/quota", reason: "quota")
    end

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :denied?
    assert_equal "/upgrade", decision.redirect_to
    assert_equal "paywall", decision.reason
    assert_equal "downloadable.stats", decision.gate
    assert_equal "paywall", decision.check
    assert_equal ["paywall"], called
  end

  def test_false_denies_without_a_redirect
    RecordingStudio.register_gate("downloadable.stats", "member") { false }

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :denied?
    assert_nil decision.redirect_to
    assert_nil decision.reason
    assert_equal "member", decision.check
  end

  def test_an_allow_decision_does_not_stop_a_later_deny
    RecordingStudio.register_gate("downloadable.stats", "open", priority: 1) do
      RecordingStudio::GateDecision.allow
    end
    RecordingStudio.register_gate("downloadable.stats", "paywall", priority: 2) { false }

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :denied?
    assert_equal "paywall", decision.check
    assert_nil decision.reason
  end

  def test_lower_priority_runs_first_and_ties_follow_registration_order
    order = []
    RecordingStudio.register_gate("downloadable.stats", "second", priority: 100) do
      order << "second"
      true
    end
    RecordingStudio.register_gate("downloadable.stats", "first", priority: 10) do
      order << "first"
      true
    end
    RecordingStudio.register_gate("downloadable.stats", "tied", priority: 100) do
      order << "tied"
      false
    end

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_equal %w[first second tied], order
    assert_equal "tied", decision.check
    names = RecordingStudio.gate_checks("downloadable.stats").map { |check| check[:name] }
    assert_equal %w[first second tied], names
  end

  def test_replacing_a_check_warns_and_uses_the_new_callable
    RecordingStudio.register_gate("downloadable.stats", "paywall") { true }
    log = capture_log do
      RecordingStudio.register_gate("downloadable.stats", "paywall") { false }
    end

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_includes log, 'Replacing check "paywall" on gate "downloadable.stats"'
    assert_predicate decision, :denied?
    assert_equal 1, RecordingStudio.gate_checks("downloadable.stats").size
  end

  def test_replacement_keeps_registration_order_for_priority_ties
    RecordingStudio.register_gate("downloadable.stats", "early", priority: 100) { false }
    RecordingStudio.register_gate("downloadable.stats", "late", priority: 100) { false }
    RecordingStudio.register_gate("downloadable.stats", "late", priority: 100) do
      RecordingStudio::GateDecision.deny(reason: "late")
    end

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_equal "early", decision.check
    assert_nil decision.reason
  end

  def test_unexpected_return_values_and_errors_deny_and_are_logged
    decision = nil
    log = capture_log do
      decision = check_only("blank") { nil }
    end
    assert_predicate decision, :denied?
    assert_nil decision.redirect_to
    assert_equal "blank", decision.check
    assert_includes log, 'Check "blank" on gate "downloadable.stats" failed closed'
    assert_includes log, "NilClass"

    assert_equal "text", check_only("text") { "yes" }.check
    assert_equal "number", check_only("number") { 1 }.check

    log = capture_log do
      decision = check_only("boom") { raise "nope" }
    end
    assert_predicate decision, :denied?
    assert_nil decision.reason
    assert_equal "boom", decision.check
    assert_includes log, 'Check "boom" on gate "downloadable.stats" failed closed'
    assert_includes log, "RuntimeError: nope"
  end

  def test_zero_arity_lambda_fails_closed
    RecordingStudio.register_gate("downloadable.stats", "strict", -> { true })
    decision = nil
    log = capture_log do
      decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)
    end

    assert_predicate decision, :denied?
    assert_equal "strict", decision.check
    assert_includes log, "ArgumentError"
  end

  def test_host_can_change_priority_and_disable_a_check
    called = []
    RecordingStudio.register_gate("downloadable.stats", "paywall", priority: 100) do
      called << "paywall"
      RecordingStudio::GateDecision.deny(redirect_to: "/upgrade", reason: "paywall")
    end
    RecordingStudio.register_gate("downloadable.stats", "legacy", priority: 100) do
      called << "legacy"
      RecordingStudio::GateDecision.deny(redirect_to: "/old", reason: "legacy")
    end

    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => {
        "paywall" => { priority: 10 },
        "legacy" => { enabled: false }
      }
    }

    checks = RecordingStudio.gate_checks("downloadable.stats")
    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_equal "paywall", checks.first[:name]
    assert_equal 10, checks.first[:priority]
    assert_equal true, checks.first[:enabled]
    assert_equal false, checks.last[:enabled]
    assert_equal ["paywall"], called
    assert_equal "/upgrade", decision.redirect_to
    assert_equal "paywall", decision.check
  end

  def test_disabled_checks_allow_when_nothing_enabled_remains
    called = false
    RecordingStudio.register_gate("downloadable.stats", "legacy") { called = true }
    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => { "legacy" => { enabled: false } }
    }

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :allowed?
    assert_equal false, called
    assert_equal true, RecordingStudio.gate_registered?("downloadable.stats")
  end

  def test_unknown_override_is_ignored_and_logged
    RecordingStudio.register_gate("downloadable.stats", "paywall") { false }
    log = capture_log do
      RecordingStudio.configuration.gate_overrides = {
        "downloadable.stats" => { "missing" => { enabled: false } }
      }
      decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)
      assert_predicate decision, :denied?
      assert_equal "paywall", decision.check
    end

    assert_includes log, 'Ignoring override for unknown check "missing" on gate "downloadable.stats"'
  end

  def test_unknown_override_warns_when_there_is_no_logger
    previous = Rails.logger
    stderr = StringIO.new
    original_stderr = $stderr
    Rails.logger = nil
    $stderr = stderr
    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => { "missing" => { enabled: false } }
    }

    decision = RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_predicate decision, :allowed?
    assert_includes stderr.string, 'Ignoring override for unknown check "missing"'
  ensure
    $stderr = original_stderr
    Rails.logger = previous
  end

  def test_clearing_overrides_restores_registered_priority
    RecordingStudio.register_gate("downloadable.stats", "paywall", priority: 80) { true }
    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => { "paywall" => { priority: 1 } }
    }
    assert_equal 1, RecordingStudio.gate_checks("downloadable.stats").first[:priority]

    RecordingStudio.configuration.gate_overrides = {}

    assert_equal 80, RecordingStudio.gate_checks("downloadable.stats").first[:priority]
  end

  def test_gate_overrides_from_merge_accept_string_keys
    RecordingStudio.configuration.merge!(
      "gate_overrides" => {
        "downloadable.stats" => {
          "legacy" => { "enabled" => false, "priority" => "4" }
        }
      }
    )

    stored = RecordingStudio.configuration.gate_overrides
    assert_equal({ priority: 4, enabled: false }, stored["downloadable.stats"]["legacy"])
    assert_predicate stored, :frozen?
  end

  def test_invalid_gate_overrides_raise_and_keep_the_previous_map
    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => { "paywall" => { priority: 3 } }
    }

    assert_raises(ArgumentError) { RecordingStudio.configuration.gate_overrides = "nope" }
    assert_raises(ArgumentError) do
      RecordingStudio.configuration.gate_overrides = { "downloadable.stats" => { "paywall" => { nope: true } } }
    end
    assert_raises(ArgumentError) do
      RecordingStudio.configuration.gate_overrides = { "downloadable.stats" => { "paywall" => { enabled: "no" } } }
    end
    assert_raises(ArgumentError) do
      RecordingStudio.configuration.gate_overrides = { "downloadable.stats" => "nope" }
    end
    assert_raises(ArgumentError) do
      RecordingStudio.configuration.gate_overrides = { "downloadable.stats" => { "paywall" => "nope" } }
    end
    assert_raises(ArgumentError) do
      RecordingStudio.register_gate("downloadable.stats", "paywall", priority: "nope") { true }
    end

    assert_equal 3, RecordingStudio.configuration.gate_overrides["downloadable.stats"]["paywall"][:priority]
  end

  def test_nil_gate_overrides_clear_the_map
    RecordingStudio.configuration.gate_overrides = {
      "downloadable.stats" => { "paywall" => { enabled: false } }
    }

    RecordingStudio.configuration.gate_overrides = nil

    assert_equal({}, RecordingStudio.configuration.gate_overrides)
  end

  def test_symbol_names_are_normalized_and_blank_names_raise
    RecordingStudio.register_gate(:"downloadable.stats", :paywall) { true }

    assert_equal true, RecordingStudio.gate_registered?("downloadable.stats")
    assert_equal "paywall", RecordingStudio.gate_checks("downloadable.stats").first[:name]
    assert_predicate RecordingStudio.check_gate(:"downloadable.stats", actor: :ada), :allowed?

    assert_raises(ArgumentError) { RecordingStudio.register_gate("", "paywall") { true } }
    assert_raises(ArgumentError) { RecordingStudio.register_gate("downloadable.stats", "  ") { true } }
    assert_raises(ArgumentError) { RecordingStudio.register_gate(1, "paywall") { true } }
    assert_raises(ArgumentError) { RecordingStudio.register_gate("downloadable.stats", "paywall") }
  end

  def test_unregister_removes_one_check_and_reset_clears_the_registry
    RecordingStudio.register_gate("downloadable.stats", "paywall") { false }
    RecordingStudio.register_gate("downloadable.stats", "quota") { false }

    assert_equal true, RecordingStudio.unregister_gate("downloadable.stats", "paywall")
    assert_equal false, RecordingStudio.unregister_gate("downloadable.stats", "missing")
    names = RecordingStudio.gate_checks("downloadable.stats").map { |check| check[:name] }
    assert_equal ["quota"], names

    RecordingStudio.unregister_gate("downloadable.stats", "quota")
    assert_equal false, RecordingStudio.gate_registered?("downloadable.stats")
    assert_predicate RecordingStudio.check_gate("downloadable.stats", actor: :ada), :allowed?

    RecordingStudio.register_gate("other.gate", "open") { false }
    RecordingStudio::Gates.reset!
    assert_equal false, RecordingStudio.gate_registered?("other.gate")
    assert_empty RecordingStudio.gate_checks("other.gate")
  end

  def test_checks_receive_actor_recording_and_context
    seen = nil
    checker = Object.new
    checker.define_singleton_method(:call) do |actor:, recording:, **context|
      seen = { actor: actor, recording: recording, context: context }
      actor == :ada
    end
    RecordingStudio.register_gate("downloadable.stats", "member", checker)

    decision = RecordingStudio.check_gate(
      "downloadable.stats",
      actor: :ada,
      recording: :recording,
      plan: "pro"
    )

    assert_equal({ actor: :ada, recording: :recording, context: { plan: "pro" } }, seen)
    assert_predicate decision, :allowed?

    omitted = nil
    RecordingStudio.register_gate("downloadable.stats", "member") do |actor:, recording:, **|
      omitted = recording
      !actor.nil?
    end
    decision = RecordingStudio.check_gate("downloadable.stats", actor: nil)
    assert_nil omitted
    assert_predicate decision, :denied?
  end

  def test_check_gate_requires_the_actor_keyword
    assert_raises(ArgumentError) { RecordingStudio.check_gate("downloadable.stats") }
  end

  def test_check_gate_does_not_call_authorize_write
    previous = RecordingStudio.configuration.authorize_write
    called = false
    RecordingStudio.configuration.authorize_write = ->(**) { called = true }
    RecordingStudio.register_gate("downloadable.stats", "paywall") { false }

    RecordingStudio.check_gate("downloadable.stats", actor: :ada)

    assert_equal false, called
  ensure
    RecordingStudio.configuration.authorize_write = previous
  end

  def test_registration_and_checks_are_safe_across_threads
    errors = Queue.new
    writers = Array.new(8) do |index|
      Thread.new do
        RecordingStudio.register_gate("load.gate", "check_#{index}") { true }
      rescue StandardError => e
        errors << e
      end
    end
    writers.each(&:join)
    assert_predicate errors, :empty?

    names = RecordingStudio.gate_checks("load.gate").map { |check| check[:name] }
    assert_equal 8, names.size
    assert_equal names.uniq, names

    results = Queue.new
    readers = Array.new(8) do
      Thread.new do
        results << RecordingStudio.check_gate("load.gate", actor: :ada).allowed?
      rescue StandardError => e
        errors << e
      end
    end
    readers.each(&:join)

    assert_predicate errors, :empty?
    assert_equal [true, true, true, true, true, true, true, true], Array.new(8) { results.pop }
  end

  def test_a_check_can_register_another_gate_without_deadlock
    RecordingStudio.register_gate("downloadable.stats", "paywall") do
      RecordingStudio.register_gate("other.gate", "open") { false }
      true
    end

    assert_predicate RecordingStudio.check_gate("downloadable.stats", actor: :ada), :allowed?
    assert_predicate RecordingStudio.check_gate("other.gate", actor: :ada), :denied?
  end

  def test_gate_decision_is_frozen_and_compares_by_value
    path = +" /upgrade"
    reason = +"paywall"
    decision = RecordingStudio::GateDecision.deny(redirect_to: path, reason: reason)
    path.replace("changed")
    reason.replace("changed")

    assert_predicate decision, :frozen?
    assert_equal " /upgrade", decision.redirect_to
    assert_equal "paywall", decision.reason
    assert_predicate decision.redirect_to, :frozen?
    assert_equal decision, RecordingStudio::GateDecision.deny(redirect_to: " /upgrade", reason: "paywall")
    other_allow = RecordingStudio::GateDecision.allow
    assert_equal false, decision == other_allow
    assert_equal other_allow, RecordingStudio::GateDecision.allow
    found = { decision => :stored }
    same = RecordingStudio::GateDecision.deny(redirect_to: " /upgrade", reason: "paywall")
    assert_equal :stored, found[same]
  end

  def test_configuration_summary_includes_gate_overrides
    summary = RecordingStudio.configuration.to_h

    assert_equal({}, summary[:gate_overrides])
  end

  def test_gem_wrapper_uses_allowed_from_check_gate
    RecordingStudio.register_gate("downloadable.stats", "paywall") do |actor:, **|
      actor == :ada ? true : RecordingStudio::GateDecision.deny(redirect_to: "/upgrade", reason: "paywall")
    end

    allowed = stats_allowed?(actor: :ada)
    denied = stats_decision(actor: :guest)

    assert_equal true, allowed
    assert_predicate denied, :denied?
    assert_equal "/upgrade", denied.redirect_to
  end

  private

  def stats_allowed?(actor:)
    stats_decision(actor: actor).allowed?
  end

  def stats_decision(actor:)
    RecordingStudio.check_gate("downloadable.stats", actor: actor)
  end

  def check_only(check_name, &)
    RecordingStudio::Gates.reset!
    RecordingStudio.configuration.gate_overrides = {}
    RecordingStudio.register_gate("downloadable.stats", check_name, &)
    RecordingStudio.check_gate("downloadable.stats", actor: :ada)
  end

  def capture_log
    @previous_logger = Rails.logger
    io = StringIO.new
    logger = Logger.new(io)
    logger.level = Logger::DEBUG
    Rails.logger = logger
    yield
    io.string
  ensure
    Rails.logger = @previous_logger
    @previous_logger = nil
  end
end
