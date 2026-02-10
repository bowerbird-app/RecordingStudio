# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# Flatpack controllers
pin "flat_pack", to: "flat_pack/index.js"
pin_all_from Gem::Specification.find_by_name("flat_pack").gem_dir + "/app/javascript/flat_pack/controllers", under: "flat_pack/controllers"
