# frozen_string_literal: true

return unless defined?(FlatPack) && FlatPack.respond_to?(:configure)

FlatPack.configure do |config|
  # === Admin Layout ===
  # Layout file used by all flatpack admin pages
  # Generate a custom layout with: bin/rails generate flatpack:layout
  # config.admin_layout = "flatpack"

  # === Admin Authentication ===
  # Host app defines custom auth logic
  # config.admin_authenticate_with = ->(controller) do
  #   controller.authenticate_admin_user!
  # end

  # === Admin Authorization ===
  # config.admin_authorize_with = ->(controller) do
  #   raise "Forbidden" unless controller.current_user.superadmin?
  # end

  # === Admin Menu Metadata ===
  # Host admin panel can read this to display menu links
  # config.menu_title = "Style Guide"
  # config.menu_group = "System"

  # === Custom Examples Path ===
  # Where host-defined custom examples live
  # config.custom_examples_path = "app/views/flatpack/custom_examples"

  # === Include Custom in Core Style Guide ===
  # Whether custom components should appear in the core style guide
  # config.include_custom_in_core_style_guide = false

  # === Additional Styling Rules ===
  # Supplemental rules beyond those in styling_rules.yml
  # config.additional_styling_rules = [
  #   "Do not exceed two accent colors per page."
  # ]

  # === Category Mapping Override ===
  # Override default category assignments for components
  # config.category_map = {
  #   "dashboard" => "data_display",
  #   "custom_component" => "misc"
  # }
end
