# frozen_string_literal: true

module RecordingStudio
  # Host map of per-check priority and enabled flags.
  # Unknown check names are kept here and ignored when a gate runs.
  module GateOverrides
    module_function

    def normalize(value)
      return {}.freeze if value.nil?
      raise ArgumentError, "gate_overrides must be a Hash" unless value.is_a?(Hash)

      value.each_with_object({}) do |(gate_name, checks), normalized|
        name = RecordingStudio::Gates.normalize_name(gate_name, "gate name")
        normalized[name] = normalize_checks(checks)
      end.freeze
    end

    def normalize_checks(checks)
      raise ArgumentError, "gate override checks must be a Hash" unless checks.is_a?(Hash)

      checks.each_with_object({}) do |(check_name, settings), normalized|
        name = RecordingStudio::Gates.normalize_name(check_name, "check name")
        normalized[name] = normalize_settings(settings)
      end.freeze
    end

    def normalize_settings(settings)
      raise ArgumentError, "gate override settings must be a Hash" unless settings.is_a?(Hash)

      settings.each_with_object({}) do |(key, setting), normalized|
        normalized[setting_key(key)] = setting_value(key, setting)
      end.freeze
    end

    def setting_key(key)
      name = key.to_sym
      return name if %i[priority enabled].include?(name)

      raise ArgumentError, "unknown gate override setting #{key.inspect}"
    end

    def setting_value(key, setting)
      case key.to_sym
      when :priority
        Integer(setting)
      when :enabled
        raise ArgumentError, "enabled must be true or false" unless [true, false].include?(setting)

        setting
      end
    end
  end
end
