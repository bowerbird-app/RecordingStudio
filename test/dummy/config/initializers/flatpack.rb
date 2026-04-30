# frozen_string_literal: true

return unless defined?(FlatPack) && FlatPack.respond_to?(:configure)

FlatPack.configure do |config|
  config.default_icon_variant = :outline if config.respond_to?(:default_icon_variant=)
end
