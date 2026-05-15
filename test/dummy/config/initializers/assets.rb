# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Include Tailwind build output for Propshaft.
builds_path = Rails.root.join("app/assets/builds")
Rails.application.config.assets.paths << builds_path unless Rails.application.config.assets.paths.include?(builds_path)
