# frozen_string_literal: true

require "securerandom"
require "simplecov"

SimpleCov.start do
  add_filter "/test/"
end

ENV["SECRET_KEY_BASE"] ||= SecureRandom.hex(64)
ENV["RAILS_ENV"] = "test"
ENV["RACK_ENV"] = "test"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)

require "minitest/autorun"
require "rails"

module FlatPack
  class Engine < ::Rails::Engine; end

  module Breadcrumb
    class Component
      def initialize(class: nil, **)
        @class_name = binding.local_variable_get(:class)
        @items = []
      end

      def item(text:, href: nil)
        @items << { text: text, href: href }
      end

      def render_in(view, &block)
        view.capture(self, &block) if block

        nodes = @items.map.with_index do |item, index|
          crumb = if item[:href]
                    view.link_to(item[:text], item[:href])
                  else
                    view.content_tag(:span, item[:text])
                  end

          next crumb if index.zero?

          view.safe_join([view.content_tag(:span, "/", class: "mx-1"), crumb])
        end

        view.content_tag(:nav, view.safe_join(nodes), class: @class_name)
      end
    end
  end

  module Card
    class Component
      def initialize(class: nil, **)
        @class_name = binding.local_variable_get(:class)
      end

      def header(**, &)
        @header = @view.capture(&) if block_given?
        nil
      end

      def body(**, &)
        @body = @view.capture(&) if block_given?
        nil
      end

      def render_in(view, &block)
        @view = view
        view.capture(self, &block) if block
        content = view.safe_join([@header, @body].compact)
        view.content_tag(:div, content, class: @class_name)
      end
    end
  end

  module RadioGroup
    class Component
      def initialize(name:, options:, value: nil, label: nil, required: false)
        @name = name
        @options = options
        @value = value
        @label = label
        @required = required
      end

      def render_in(view)
        legend = @label ? view.content_tag(:legend, @label, class: "text-sm font-medium text-slate-500") : "".html_safe
        inputs = @options.map do |option_label, option_value|
          checked = option_value.to_s == @value.to_s
          input = view.tag.input(type: "radio", name: @name, value: option_value, checked: checked, required: @required)
          view.content_tag(:label, view.safe_join([input, view.content_tag(:span, option_label, class: "ml-2")]),
                           class: "inline-flex items-center")
        end
        view.content_tag(:fieldset, view.safe_join([legend, view.safe_join(inputs, view.tag.br)]), class: "space-y-2")
      end
    end
  end

  module Button
    class Component
      def initialize(text:, url: nil, **)
        @text = text
        @url = url
      end

      def render_in(view)
        return view.link_to(@text, @url, class: "inline-flex items-center") if @url

        view.content_tag(:button, @text, type: "button", class: "inline-flex items-center")
      end
    end
  end

  module Badge
    class Component
      def initialize(text:, **)
        @text = text
      end

      def render_in(view)
        view.content_tag(:span, @text, class: "inline-flex rounded px-2 py-0.5 text-xs")
      end
    end
  end

  module Table
    class Component
      def initialize(data:, **)
        @data = data
        @columns = []
      end

      def column(title:, html:)
        @columns << { title: title, html: html }
      end

      def render_in(view, &block)
        view.capture(self, &block) if block

        header = view.content_tag(:thead) do
          view.content_tag(:tr) do
            view.safe_join(@columns.map do |col|
              view.content_tag(:th, col[:title], class: "px-4 py-2 text-left text-sm")
            end)
          end
        end

        body = view.content_tag(:tbody) do
          rows = @data.map do |row|
            view.content_tag(:tr) do
              cells = @columns.map do |col|
                value = col[:html].respond_to?(:call) ? col[:html].call(row) : ""
                view.content_tag(:td, value, class: "px-4 py-2 text-sm")
              end
              view.safe_join(cells)
            end
          end
          view.safe_join(rows)
        end

        view.content_tag(:table, view.safe_join([header, body]), class: "min-w-full")
      end
    end
  end

  module TextInput
    class Component
      def initialize(name:, label: nil, value: nil, required: false, type: "text")
        @name = name
        @label = label
        @value = value
        @required = required
        @type = type
      end

      def render_in(view)
        label = @label ? view.content_tag(:label, @label, class: "text-sm font-medium") : "".html_safe
        input = view.tag.input(type: @type, name: @name, value: @value, required: @required,
                               class: "w-full rounded border px-3 py-2")
        view.safe_join([label, input])
      end
    end
  end

  module EmailInput
    class Component < TextInput::Component
      def initialize(**)
        super(type: "email", **)
      end
    end
  end

  module PasswordInput
    class Component < TextInput::Component
      def initialize(**)
        super(type: "password", **)
      end
    end
  end

  module Checkbox
    class Component
      def initialize(name:, label:, value: "1", checked: false, **)
        @name = name
        @label = label
        @value = value
        @checked = checked
      end

      def render_in(view)
        input = view.tag.input(type: "checkbox", name: @name, value: @value, checked: @checked)
        view.content_tag(:label, view.safe_join([input, view.content_tag(:span, @label, class: "ml-2")]),
                         class: "inline-flex items-center")
      end
    end
  end
end

require File.expand_path("dummy/config/environment", __dir__)
require "rails/test_help"
require "recording_studio"

ActiveSupport::TestCase.class_eval do
  def assert_not(value, message = nil)
    assert_equal false, !!value, message
  end

  def assert_not_nil(value, message = nil)
    assert_equal false, value.nil?, message
  end
end

Minitest::Test.class_eval do
  def assert_not(value, message = nil)
    assert_equal false, !!value, message
  end

  def assert_not_nil(value, message = nil)
    assert_equal false, value.nil?, message
  end
end
