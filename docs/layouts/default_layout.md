# RecordingStudio Default Layout

`recording_studio/default_layout` is the one shared page shell. It does not
assume a sidebar, a host application layout, or a page kind. The public
layout file wraps `app/views/recording_studio/shared/_default_layout.html.erb`.

The page nav is back and anchor only. Back is always shown. The anchor
(close) is shown when the view sets `page_nav_anchor_url`. Icons, button
style, and button size are fixed: back is `chevron-left` / secondary / md,
and the anchor is `x-mark`.

> **Prerequisite:** `flat_pack` is a required dependency (`>= 0.1.275`).
> The layout renders `FlatPack::PageNav::Component` and
> `FlatPack::Alert::Component`. There is no fallback when Flatpack is
> missing. `flat_pack` is not on RubyGems. The gemspec declares the
> dependency, and the host Gemfile supplies the git source
> (`https://github.com/bowerbird-app/flatpack.git`, tag `v0.1.275`).

## What it provides

- Back and anchor page nav, plus an optional right-hand slot.
- Flash notice and alert via `FlatPack::Alert::Component`.
- The page body via `yield`, with no extra content card.
- `<title>`, optional description, and OpenGraph title, type, url,
  description, and site name.
- `yield :head`, and `recording_studio/_default_layout_head` when that
  partial is on the view path.
- Flatpack stylesheets `flat_pack/variables` and `flat_pack/rich_text`.
- `data-theme="rounded"` on `<body>`.
- Title and site-name fallback from `RecordingStudio.configuration.app_name`.

## Opting in from a controller

Call the class macro on the gem's base controller. Subclasses inherit it
through Rails.

```ruby
class ApplicationController < ActionController::Base
  recording_studio_layout { RecordingStudioX.configuration.layout }
end
```

The macro stores the block, defines `recording_studio_resolved_layout`,
declares `layout :recording_studio_resolved_layout`, and adds
`helper RecordingStudio::LayoutHelper`. The block is evaluated in the
controller with no arguments and returns that surface's layout setting.

Lookup uses the first value that is not `nil`:

1. The block's setting.
2. `RecordingStudio.configuration.layout`.
3. `RecordingStudio::DEFAULT_LAYOUT` (`"recording_studio/default_layout"`).

`false` means no layout and does not fall through. A callable is invoked as
`call(controller:)` and returns a String, `nil`, or `false`. A positional
parameter raises `ArgumentError`.

`layout "name"` or `layout false` on a subclass replaces the inherited
resolver. `RecordingStudio::ApplicationController` calls the macro with no
block, so core screens use the same lookup and no longer default to
`"application"`.

Do not hard-code `layout "recording_studio/default_layout"`.
`RecordingStudio::Layout.hardcoded_layout_paths(root)` and
`rake recording_studio:check_layouts` report those calls.

## Gem adoption

One setting per surface, defaulting to `nil`. Each surface has its own base
controller and its own block. A `nil` setting lets the host's core layout,
then `RecordingStudio::DEFAULT_LAYOUT`, decide.

```ruby
module RecordingStudioLibrary
  class Configuration
    attr_accessor :library_layout, :editor_layout

    def initialize
      @library_layout = nil
      @editor_layout = nil
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end
end

module Library
  class ApplicationController < ActionController::Base
    recording_studio_layout { RecordingStudioLibrary.configuration.library_layout }
  end
end

module Editor
  class ApplicationController < ActionController::Base
    recording_studio_layout { RecordingStudioLibrary.configuration.editor_layout }
  end
end
```

The two blocks resolve independently. A host can set one without changing
the other.

## Hosts

Set the core default for every gem whose block returns `nil`:

```ruby
RecordingStudio.configure do |config|
  config.layout = "application"
end
```

Or a callable:

```ruby
RecordingStudio.configure do |config|
  config.layout = ->(controller:) { "application" }
end
```

Override one gem surface. That setting wins over the core default:

```ruby
RecordingStudioLibrary.configuration.library_layout = "library"
# editor_layout stays nil, so the editor follows configuration.layout
```

Leave both unset to use `RecordingStudio::DEFAULT_LAYOUT`.

Set the app name used when a view does not set a title:

```ruby
RecordingStudio.configure do |config|
  config.app_name = "My App"
end
```

## Host layout contract

Gem views set `content_for` slots and render Flatpack components. They do
not draw the application shell. A host layout that replaces the default
has to provide the same surroundings, or titles, navigation, and flashes
disappear.

Slots gem views set:

| Slot | How views set it | Who uses it |
| --- | --- | --- |
| `:title` | `recording_studio_page_nav(title:)` or `content_for :title` | Library, pages, admin, API, brands, broadcasts, company, embargo, messages, orderable, publishable, stripe, support, trashable, users, embeddable, OAuth, notifications |
| `:head` | `default_layout_head` or `content_for :head` | Moveable (meta tags), stripe billing (stylesheet), embeddable (`recording_studio/_default_layout_head`) |
| `:seo_description` | `recording_studio_seo_description` | Support public pages |
| `:page_nav_back_url` | `recording_studio_page_nav` | Embeddable, OAuth, API, company, embargo, library, pages, publishable, stripe, support, and others |
| `:page_nav_back_label` | `recording_studio_page_nav` | Company, embargo, pages, support, and others |
| `:page_nav_anchor_url` | `recording_studio_page_nav` | Embeddable, library, moveable, orderable, publishable, stripe, support, trashable, users |
| `:page_nav_anchor_label` | `recording_studio_page_nav` | Embeddable, library, moveable, orderable, publishable, support, trashable, users |
| `:page_nav_right` | `recording_studio_page_nav_right` | Admin section and screen pages, API scalar docs, publishable job nav |

Also required:

- Stylesheets `flat_pack/variables` and `flat_pack/rich_text`, plus the
  importmap when the host defines `javascript_importmap_tags`.
- `flash[:notice]` and `flash[:alert]` rendered with
  `FlatPack::Alert::Component`. OAuth, brands, embargo, features, library,
  messages, notifications, pages, publishable, stripe, support, and users
  set flash and rely on the layout to show it.

`FlatPack::SidebarLayout::Component` is the application shell (sidebar,
optional top nav, and main). The dummy `application` layout uses it. Put
the page, including alerts, in the `main` slot. Flatpack does not ship a
`PageLayout` component. This default layout is the page shell.

The layout does not read `:body_theme`, `:seo_image`, page-nav icon, style,
or size slots. No gem view sets those. Back and anchor icons stay
`chevron-left` and `x-mark`.

## Helper API

- `recording_studio_page_nav(title: nil, page_nav_back_url:, page_nav_back_label:, page_nav_anchor_url:, page_nav_anchor_label:)`
- `recording_studio_page_nav_right { ... }`
- `default_layout_head { ... }`
- `recording_studio_seo_description(text)`

## Defaults

| Piece | Default |
| --- | --- |
| Title | `content_for(:title)` → `RecordingStudio.configuration.app_name` → `"CHANGE_APP_NAME_IN_DEFAULT_LAYOUT"` |
| Theme | `data-theme="rounded"` |
| Description | Omitted when blank |
| `og:title` | Same as `<title>` |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| Back | Always shown through `FlatPack::PageNav` `with_back`. Icon `chevron-left`, style secondary, size md. Label is `page_nav_back_label` or "Go back". `page_nav_back_url` is the href. With no URL, PageNav renders a history-back button (`click->flat-pack--page-nav#back`) and uses `page_nav_anchor_url` as `fallback_url` when that URL is set. |
| Anchor | Hidden unless `page_nav_anchor_url` is set. Icon `x-mark`. Label is `page_nav_anchor_label` or "Close". The layout does not read `params`. |
| Right slot | Empty until `page_nav_right` is set. Then it sits in a trailing `ml-auto` row item. |

## Page nav example

```erb
<% recording_studio_page_nav(
  title: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_label: "Home"
) %>

<% recording_studio_page_nav_right do %>
  <%= render FlatPack::Button::Component.new(
    icon: "plus",
    icon_only: true,
    style: :secondary,
    size: :md,
    url: new_workspace_path,
    aria: { label: "Add workspace" }
  ) %>
<% end %>
```

Back and anchor together:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_back_url: workspaces_path,
  page_nav_back_label: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_label: "Home"
) %>
```

## SEO

| Tag | Source |
| --- | --- |
| `og:title` | Same fallback chain as `<title>` |
| `og:type` | `"website"` |
| `og:url` | `request.original_url` |
| `og:description` | `content_for(:seo_description)` when present |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| `<meta name="description">` | `content_for(:seo_description)` when present |

```erb
<% recording_studio_seo_description("Workspaces overview for your team") %>
```

### Optional head partial

A gem can ship `app/views/recording_studio/_default_layout_head.html.erb`.
The layout renders it before `yield :head` when the partial is found.
Embeddable uses that partial for shared head markup. Moveable calls
`default_layout_head` from the view instead. Stripe billing uses
`content_for :head` for its button stylesheet.

## Interface text

Back and close labels and the nav `aria-label` ship as English keys under
`recording_studio.core.navigation` in `config/locales/en.yml`, looked up
through `RecordingStudio.t`. A missing locale falls back to the loaded `:en`
translation and then the gem-shipped table. Hosts can override
`go_back`, `close`, and `page`. A view that passes
`page_nav_back_label` or `page_nav_anchor_label` uses that string.

The developer placeholder `CHANGE_APP_NAME_IN_DEFAULT_LAYOUT` is not
translated.

## Testing

```ruby
class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  test "index renders default layout with page nav" do
    get workspaces_path

    assert_response :success
    assert_select "title", text: "Workspaces"
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
  end
end
```

`data-recording-studio-default-layout="true"` on `<body>` confirms the
layout is active.
