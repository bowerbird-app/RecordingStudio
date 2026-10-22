# frozen_string_literal: true

require "test_helper"
require "yaml"

class LocalesTest < ActiveSupport::TestCase
  NAVIGATION_KEYS = {
    "back" => "Back",
    "page" => "Page navigation",
    "action_page" => "Action page navigation"
  }.freeze

  LABEL_KEYS = {
    "empty" => "—"
  }.freeze

  test "engine ships only english locale files" do
    files = Dir[File.join(engine_locales_dir, "*")].map { |path| File.basename(path) }

    assert_equal ["en.yml"], files.sort
  end

  test "rails i18n load path includes the gem english locale file" do
    locale_path = File.join(engine_locales_dir, "en.yml")

    assert_includes I18n.load_path.map { |path| File.expand_path(path) }, File.expand_path(locale_path)
  end

  test "lib sources do not append i18n load path" do
    lib_dir = File.expand_path("../lib", __dir__)
    ruby_files = Dir[File.join(lib_dir, "**", "*.rb")]

    refute_empty ruby_files, "expected lib/**/*.rb files to scan"

    ruby_files.each do |path|
      source = File.read(path)

      refute_includes source, "i18n.load_path", "#{path} must not touch i18n.load_path"
      refute_includes source, "I18n.load_path", "#{path} must not touch I18n.load_path"
    end
  end

  test "english navigation keys resolve without missing translations" do
    I18n.with_locale(:en) do
      NAVIGATION_KEYS.each do |key, english|
        full_key = "recording_studio.core.navigation.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end
    end
  end

  test "english label keys resolve without missing translations" do
    I18n.with_locale(:en) do
      LABEL_KEYS.each do |key, english|
        full_key = "recording_studio.core.labels.#{key}"
        translation = I18n.t(full_key, default: nil)

        assert_equal english, translation, "#{full_key} should resolve to #{english.inspect}"
        assert_equal english, I18n.t(full_key, raise: true)
      end
    end
  end

  test "en.yml nests keys under recording_studio.core" do
    core = locale_tree(File.join(engine_locales_dir, "en.yml"), "en")
           .fetch("recording_studio")
           .fetch("core")

    assert_equal NAVIGATION_KEYS, core.fetch("navigation").transform_keys(&:to_s)
    assert_equal LABEL_KEYS, core.fetch("labels").transform_keys(&:to_s)
  end

  test "shipped en.yml keys resolve through RecordingStudio.t in en and missing locales" do
    shipped = shipped_english_keys
    previous_locales = I18n.available_locales
    I18n.available_locales = (previous_locales + %i[en de]).uniq

    shipped.each do |full_key, english|
      I18n.with_locale(:en) do
        assert_equal english, RecordingStudio.t(full_key)
      end

      I18n.with_locale(:de) do
        refute I18n.exists?(full_key, :de)
        assert_equal english, RecordingStudio.t(full_key),
                     "#{full_key}: missing-locale fallback must match en.yml"
      end
    end
  ensure
    I18n.available_locales = previous_locales if previous_locales
  end

  test "every RecordingStudio.t call site key exists in en.yml and has no default" do
    shipped = shipped_english_keys
    roots = [
      File.expand_path("../app", __dir__),
      File.expand_path("../lib", __dir__)
    ]
    files = roots.flat_map { |root| Dir[File.join(root, "**", "*.{rb,erb}")] }
    refute_empty files

    offenders = []
    unknown_keys = []

    files.each do |path|
      source = File.read(path)
      each_translation_call_args(source) do |method_name, args|
        keys = extract_recording_studio_keys(args)
        next if keys.empty? && !args.match?(/recording_studio/)

        keys.each do |key|
          unknown_keys << "#{path}: #{key}" unless shipped.key?(key)
        end

        next unless args.match?(/\bdefault:\s*/)

        offenders << "#{path}: #{method_name}(... default: ...) args=#{args.gsub(/\s+/, ' ').strip[0, 120]}"
      end
    end

    assert_empty unknown_keys,
                 "RecordingStudio.t keys must exist in en.yml; unknown: #{unknown_keys.join(', ')}"
    assert_empty offenders,
                 "gem recording_studio lookups must not pass default:; found: #{offenders.join(', ')}"
  end

  test "scanner catches EMPTY_LABEL single-quoted multi-line I18n.translate Array and paren-less defaults" do
    samples = {
      empty_label: <<~RUBY,
        RecordingStudio.t("recording_studio.core.labels.empty", default: EMPTY_LABEL)
      RUBY
      single_quoted: <<~RUBY,
        RecordingStudio.t('recording_studio.core.navigation.back', default: 'Back')
      RUBY
      multi_line: <<~RUBY,
        RecordingStudio.t(
          "recording_studio.core.navigation.go_back",
          default: "Go back"
        )
      RUBY
      i18n_translate: <<~RUBY,
        I18n.translate("recording_studio.core.navigation.close", default: "Close")
      RUBY
      array_default: <<~RUBY,
        I18n.t("recording_studio.core.navigation.page", default: ["Page navigation", "Fallback"])
      RUBY
      bare_t: <<~RUBY,
        t("recording_studio.core.navigation.action_page", default: "Action page navigation")
      RUBY
      paren_less: <<~RUBY
        RecordingStudio.t "recording_studio.core.navigation.back", default: "Back"
      RUBY
    }

    samples.each do |name, source|
      found = false
      each_translation_call_args(source) do |_method_name, args|
        found = true if args.match?(/\bdefault:\s*/)
      end
      assert found, "scanner must catch #{name} default: form"
    end
  end

  test "gemspec does not depend on internationalization" do
    gemspec = File.read(File.expand_path("../recording_studio.gemspec", __dir__))

    refute_includes gemspec, "recording_studio_internationalization"
    refute_includes gemspec, "RecordingStudio_Internationalization"
  end

  test "dummy gemfile does not depend on internationalization" do
    gemfile = File.read(File.expand_path("dummy/Gemfile", __dir__))

    refute_includes gemfile, "recording_studio_internationalization"
    refute_includes gemfile, "RecordingStudio_Internationalization"
  end

  private

  def engine_locales_dir
    File.expand_path("../config/locales", __dir__)
  end

  def locale_tree(path, locale)
    YAML.safe_load_file(path, aliases: true).fetch(locale)
  end

  def shipped_english_keys
    tree = locale_tree(File.join(engine_locales_dir, "en.yml"), "en").fetch("recording_studio")
    flatten_locale_keys(tree, ["recording_studio"])
  end

  def flatten_locale_keys(node, prefix)
    case node
    when Hash
      node.each_with_object({}) do |(key, value), result|
        result.merge!(flatten_locale_keys(value, prefix + [key.to_s]))
      end
    else
      { prefix.join(".") => node }
    end
  end

  def each_translation_call_args(source)
    pattern = /
      (?:RecordingStudio(?:::Translation)?\.t|I18n\.(?:t|translate)|(?<![\w.:])t)
      (?:
        \s*\(
        |
        \s+(?=["'])
      )
    /mx
    offset = 0
    while (match = pattern.match(source, offset))
      method_name = match[0].sub(/\s*[(]\z/, "").sub(/\s+\z/, "")
      args_start = match.end(0)
      if match[0].include?("(")
        args, args_end = read_balanced_args(source, args_start)
      else
        args, args_end = read_paren_less_args(source, args_start)
      end
      yield method_name, args
      offset = args_end
    end
  end

  def read_paren_less_args(source, start_index)
    index = start_index
    in_single = false
    in_double = false
    escape = false

    while index < source.length
      char = source[index]
      break if !in_single && !in_double && %W[\n ;].include?(char)

      if escape
        escape = false
      elsif char == "\\" && (in_single || in_double)
        escape = true
      elsif char == "'" && !in_double
        in_single = !in_single
      elsif char == '"' && !in_single
        in_double = !in_double
      end
      index += 1
    end

    [source[start_index...index], index]
  end

  def read_balanced_args(source, start_index)
    depth = 1
    index = start_index
    in_single = false
    in_double = false
    escape = false

    while index < source.length && depth.positive?
      char = source[index]

      if escape
        escape = false
      elsif char == "\\" && (in_single || in_double)
        escape = true
      elsif char == "'" && !in_double
        in_single = !in_single
      elsif char == '"' && !in_single
        in_double = !in_double
      elsif !in_single && !in_double
        case char
        when "(" then depth += 1
        when ")" then depth -= 1
        end
      end

      index += 1
    end

    [source[start_index...(index - 1)], index]
  end

  def extract_recording_studio_keys(args)
    keys = []
    args.scan(/["'](recording_studio\.[^"']+)["']/) { |match| keys << match[0] }
    if (match = args.match(/%w\[([^\]]+)\]/))
      match[1].split.each do |token|
        keys << token if token.start_with?("recording_studio.")
      end
    end
    keys
  end
end
