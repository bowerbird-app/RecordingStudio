// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { initLocalTimes } from "flat_pack/local_time"

document.addEventListener("DOMContentLoaded", () => {
  initLocalTimes()
})

document.addEventListener("turbo:load", () => {
  initLocalTimes()
})
