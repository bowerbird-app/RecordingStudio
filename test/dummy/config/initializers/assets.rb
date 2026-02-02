# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# Rails.application.config.assets.paths << Emoji.images_path

# Add MakeupArtist gem JavaScript path for Propshaft (Rails 8+)
begin
	makeup_artist_dir = Gem::Specification.find_by_name("makeup_artist").gem_dir
	Rails.application.config.assets.paths << "#{makeup_artist_dir}/app/javascript"
rescue Gem::LoadError
	# Skip when the gem is not available (test environment)
end
