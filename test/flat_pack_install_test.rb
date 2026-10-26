# frozen_string_literal: true

require "test_helper"

class FlatPackInstallTest < ActiveSupport::TestCase
  test "dummy tailwind entry scans flatpack and does not copy kit tokens" do
    css = File.read(Rails.root.join("app/assets/tailwind/application.css"))

    assert_includes css, '@import "tailwindcss" source(none);'
    assert_includes css, '@source "../../../vendor/bundle/ruby/3.3.0/bundler/gems/flatpack-c289e1ee98b9/app/components"'
    assert_includes css, "app/helpers"
    refute_match(/^\s*--font-sans:/, css)
    refute_match(/^\s*--font-mono:/, css)
    refute_match(/^\s*--radius-/, css)
    refute_match(/^\s*--color-fp-/, css)
    refute_includes css, "@layer base"
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
