# frozen_string_literal: true

require "test_helper"

class FlatPackInstallTest < ActiveSupport::TestCase
  test "dummy tailwind entry re-sets the kit face and the full radius scale" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))

    assert_includes css, '--font-sans: system-ui, "Segoe UI", Roboto, Helvetica, Arial, sans-serif'
    assert_includes css, '--font-mono: ui-monospace, "SF Mono", Menlo, Consolas'
    assert_includes css, "--radius-md: 0.5rem;"
    assert_includes css, "--radius-xxl: 2rem;"
    assert_includes css, "--radius-xxxl: 2.5rem;"
    assert_includes css, "--radius-full: 9999px;"
    refute_match(/^\s*--color-fp-/, css)
  end

  test "dummy javascript initializes local times and pins the current tiptap packages" do
    javascript = File.read(Rails.root.join("app/javascript/application.js"))
    importmap = File.read(Rails.root.join("config/importmap.rb"))

    assert_includes javascript, 'import { initLocalTimes } from "flat_pack/local_time"'
    assert_includes javascript, 'document.addEventListener("DOMContentLoaded"'
    assert_includes javascript, 'document.addEventListener("turbo:load"'
    assert_includes importmap, 'pin "@tiptap/extension-audio"'
    assert_includes importmap, 'pin "@tiptap/extension-trailing-node"'
    assert_includes importmap, 'pin "flat_pack/local_time"'
  end
end
