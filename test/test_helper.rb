# frozen_string_literal: true

require "securerandom"
require "simplecov"

SimpleCov.start do
  add_filter "/test/"
end

ENV["SECRET_KEY_BASE"] ||= SecureRandom.hex(64)
ENV["RAILS_ENV"] = "test"
ENV["RACK_ENV"] = "test"
ENV["DB_USER"] ||= "postgres"
ENV["DB_PASSWORD"] ||= "postgres"
ENV["DB_HOST"] ||= "localhost"
ENV["DB_PORT"] ||= "5432"
ENV["DB_NAME_TEST"] ||= ENV.fetch("DB_NAME", "gem_template_test")
db_user = ENV.fetch("DB_USER", nil)
db_password = ENV.fetch("DB_PASSWORD", nil)
db_host = ENV.fetch("DB_HOST", nil)
db_port = ENV.fetch("DB_PORT", nil)
db_name_test = ENV.fetch("DB_NAME_TEST", nil)

ENV["PGUSER"] ||= db_user
ENV["PGPASSWORD"] ||= db_password
ENV["DATABASE_URL"] ||= "postgres://#{db_user}:#{db_password}@#{db_host}:#{db_port}/#{db_name_test}"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift File.expand_path("../app/models", __dir__)

require "minitest/autorun"
require "rails"

module RecordingStudioTestDataHelpers
  def reset_recording_studio_tables!(*recordable_classes)
    RecordingStudio::Event.delete_all
    RecordingStudio::Recording.unscoped.update_all(parent_recording_id: nil, root_recording_id: nil)
    RecordingStudio::Recording.unscoped.delete_all

    recordable_classes.compact.uniq.each(&:delete_all)
    Workspace.delete_all if defined?(Workspace)
    User.delete_all if defined?(User)
  end
end

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

  module PageHeader
    class Component
      def initialize(title:, subtitle: nil, class: nil, title_tag: :h2, **)
        @title = title
        @subtitle = subtitle
        @class_name = binding.local_variable_get(:class)
        @title_tag = title_tag
      end

      def render_in(view, &block)
        actions = block ? view.capture(&block) : nil
        title = view.content_tag(@title_tag, @title, class: "text-2xl font-semibold text-slate-900")
        subtitle = if @subtitle.present?
                     view.content_tag(:p, @subtitle, class: "text-sm text-slate-500")
                   else
                     "".html_safe
                   end

        sections = [view.content_tag(:div, view.safe_join([title, subtitle]), class: "space-y-1")]
        sections << view.content_tag(:div, actions, class: "flex flex-wrap items-center gap-2") if actions.present?

        view.content_tag(:div, view.safe_join(sections), class: [@class_name, "space-y-3"].compact.join(" "))
      end
    end
  end

  module Alert
    class Component
      STYLES = {
        notice: "rounded-md border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-800",
        alert: "rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800",
        info: "rounded-md border border-slate-200 bg-white px-4 py-3 text-sm text-slate-700"
      }.freeze

      def initialize(message:, tone: :info, class: nil, **)
        @message = message
        @tone = tone.to_sym
        @class_name = binding.local_variable_get(:class)
      end

      def render_in(view)
        base_class = STYLES.fetch(@tone, STYLES[:info])
        view.content_tag(:div, @message, class: [@class_name, base_class].compact.join(" "))
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
      def initialize(text: nil, **attributes)
        @text = text
        @url = attributes[:url]
        @type = attributes.fetch(:type, "button")
        @class_name = attributes[:class]
        @data = attributes[:data]
        @form = attributes[:form]
        @aria_label = attributes[:aria_label]
      end

      def render_in(view, &block)
        classes = ["inline-flex items-center", @class_name].compact.join(" ")
        content = block ? view.capture(&block) : @text

        if @url
          return view.link_to(@url, class: classes, data: @data) do
            content
          end
        end

        view.content_tag(
          :button,
          content,
          type: @type,
          class: classes,
          data: @data,
          form: @form,
          aria: { label: @aria_label }
        )
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
        @actions = []
      end

      def column(title:, html:)
        @columns << { title: title, html: html }
      end

      def with_action(text:, url:, **)
        @actions << { text: text, url: url }
      end

      def render_in(view, &block)
        view.capture(self, &block) if block
        columns = @columns + action_columns(view)

        header = view.content_tag(:thead) do
          view.content_tag(:tr) do
            view.safe_join(columns.map do |col|
              view.content_tag(:th, col[:title], class: "px-4 py-2 text-left text-sm")
            end)
          end
        end

        body = view.content_tag(:tbody) do
          rows = @data.map do |row|
            view.content_tag(:tr) do
              cells = columns.map do |col|
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

      private

      def action_columns(view)
        return [] if @actions.empty?

        [
          {
            title: "Actions",
            html: lambda { |row|
              links = @actions.map do |action|
                href = action[:url].respond_to?(:call) ? action[:url].call(row) : action[:url]
                view.link_to(action[:text], href)
              end
              view.safe_join(links, " ".html_safe)
            }
          }
        ]
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

  module TextArea
    class Component
      def initialize(name:, **attributes)
        @name = name
        @label = attributes[:label]
        @value = attributes[:value]
        @required = attributes.fetch(:required, false)
        @rows = attributes.fetch(:rows, 4)
      end

      def render_in(view)
        label = @label ? view.content_tag(:label, @label, class: "text-sm font-medium") : "".html_safe
        input = view.content_tag(
          :textarea,
          @value,
          name: @name,
          required: @required,
          rows: @rows,
          class: "w-full rounded border px-3 py-2"
        )
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
require "devise/test/integration_helpers"

ActiveSupport::TestCase.class_eval do
  include RecordingStudioTestDataHelpers

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

module ActionDispatch
  class IntegrationTest
    include Devise::Test::IntegrationHelpers

    MODERN_USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 " \
                        "(KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    def create_user(
      name: "Test User",
      email: "user-#{SecureRandom.hex(4)}@example.com",
      admin: false
    )
      User.create!(
        name: name,
        email: email,
        password: "password123",
        password_confirmation: "password123",
        admin: admin
      )
    end

    def sign_in_as(user)
      sign_in user, scope: :user
    end

    def modern_headers(extra_headers = {})
      { "HTTP_USER_AGENT" => MODERN_USER_AGENT }.merge(extra_headers)
    end
  end
end
