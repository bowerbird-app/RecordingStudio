# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Include Tailwind build output for Propshaft.
Rails.application.config.assets.paths << Rails.root.join("app/assets/builds")

# Add Flatpack gem JavaScript path for Propshaft (Rails 8+)
begin
	flat_pack_dir = Gem::Specification.find_by_name("flat_pack").gem_dir
	Rails.application.config.assets.paths << "#{flat_pack_dir}/app/javascript"
rescue Gem::LoadError
	# Skip when the gem is not available (test environment)
end
