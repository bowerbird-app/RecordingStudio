// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { application } from "controllers/application"

// Flatpack Stimulus Controllers
import * as FlatPack from "flat_pack"
FlatPack.register(application)
