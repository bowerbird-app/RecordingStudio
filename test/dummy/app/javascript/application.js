// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { application } from "controllers/application"

// Flatpack Stimulus Controllers
import("flat_pack")
	.then((FlatPack) => {
		FlatPack.register(application)
	})
	.catch(() => {
	})
