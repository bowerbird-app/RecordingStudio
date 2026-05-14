# frozen_string_literal: true

module FlatPack
  class Engine < ::Rails::Engine; end

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

        sections = [ view.content_tag(:div, view.safe_join([ title, subtitle ]), class: "space-y-1") ]
        sections << view.content_tag(:div, actions, class: "flex flex-wrap items-center gap-2") if actions.present?

        view.content_tag(:div, view.safe_join(sections), class: [ @class_name, "space-y-3" ].compact.join(" "))
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
        classes = [ "inline-flex items-center", @class_name ].compact.join(" ")
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
        view.content_tag(:div, @message, class: [ @class_name, base_class ].compact.join(" "))
      end
    end
  end
end
