# RecordingStudio Default Layout

`recording_studio/default_layout` is the one shared page shell. It does not
assume a sidebar, a host application layout, or a page kind. The public
layout file wraps `app/views/recording_studio/shared/_default_layout.html.erb`.

Page navigation is Flatpack's. A view calls `flat_pack_page_nav` for the
back and anchor row. The layout calls `flat_pack_page_nav_tag`. That tag
renders the registered row and fills a blank anchor from a valid
`params[:return_to]` (`FlatPack::ReturnTo`). It returns nil when the view
registered nothing and there is no valid `return_to`. The layout does not
add an icon row of its own. Core does not choose an anchor, does not read
`return_to` itself, and has no way to hide the back button.

The page header is separate. When the view sets `content_for :title`, the
layout renders `FlatPack::PageTitle` with that title and an optional
`content_for :subtitle`. It skips the header when the title is blank. The
same `:title` value is the document `<title>`.

Page buttons are separate from form buttons. A view calls
`register_page_nav` for the buttons that belong with the page (Browse, New,
and the like). The layout renders them with `render_page_nav(:top_nav)` on
the same row as the back and anchor, right-aligned. That row shows when
either side has content. The title and subtitle stay below it, with no
actions row. Submit and cancel stay in the form. `register_page_nav` is not
`flat_pack_page_nav`.

> **Prerequisite:** `flat_pack` is a required dependency (`>= 0.1.296`).
> The layout renders `flat_pack_page_nav_tag`, `render_page_nav(:top_nav)`,
> `FlatPack::PageTitle`, and `FlatPack::Alert`. It links
> `flat_pack/variables`, `flat_pack/application`, and `flat_pack/rich_text`.
> There is no fallback when Flatpack is missing. `flat_pack` is not on
> RubyGems. The gemspec declares the dependency, and the host Gemfile
> supplies the git source
> (`https://github.com/bowerbird-app/flatpack.git`, tag `v0.1.296`).

## What it provides

- Back and anchor page nav through `flat_pack_page_nav_tag`, on the left of one row.
- Registered page buttons through `render_page_nav(:top_nav)`, right-aligned on that row. The row wraps when the buttons do not fit.
- A `FlatPack::PageTitle` when `content_for :title` is set, with an optional
  subtitle from `content_for :subtitle`. No actions row under the title.
- Flatpack kit CSS (`flat_pack/application`) so those buttons take their style.
- Flash notice and alert via `FlatPack::Alert`.
- The page body via `yield`, with no extra content card.
- `<title>`, optional description, and OpenGraph title, type, url,
  description, and site name.
- `yield :head`, and `recording_studio/_default_layout_head` when that
  partial is on the view path.
- Flatpack stylesheets `flat_pack/variables`, `flat_pack/application`, and `flat_pack/rich_text`.
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

Gem views set `content_for` slots and register Flatpack page nav and page
actions. They do not draw the application shell or their own page title.
A host layout that replaces the default renders one row: `flat_pack_page_nav_tag`
on the left and `render_page_nav(:top_nav)` on the right. The row shows when
either side has content. Then `FlatPack::PageTitle` from `:title` and
`:subtitle` when a title is set. Without those pieces, titles, navigation,
actions, and flashes disappear. Link
`flat_pack/application` so button fills paint.

Slots gem views set:

| Slot | How views set it | Who uses it |
| --- | --- | --- |
| `:title` | `content_for :title` | Document `<title>` and `FlatPack::PageTitle`. Required for the header to show. Library, pages, admin, API, brands, broadcasts, company, embargo, messages, orderable, publishable, stripe, support, trashable, users, embeddable, OAuth, notifications |
| `:subtitle` | `content_for :subtitle` | Optional `FlatPack::PageTitle` subtitle |
| `:head` | `default_layout_head` or `content_for :head` | Moveable (meta tags), stripe billing (stylesheet), embeddable (`recording_studio/_default_layout_head`) |
| `:seo_description` | `recording_studio_seo_description` | Support public pages |

Flatpack request state the host layout must render:

| Call | How views set it | What the layout renders |
| --- | --- | --- |
| `flat_pack_page_nav` | back href and tooltip, anchor href and tooltip | `flat_pack_page_nav_tag`. A valid `return_to` fills a blank anchor. Nil means nothing was registered and there is no `return_to`. The layout leaves that nil alone. |
| `register_page_nav` | label, href, role, icon | `render_page_nav(:top_nav)`, right-aligned on the nav row |

Also required:

- Stylesheets `flat_pack/variables`, `flat_pack/application`, and `flat_pack/rich_text`, plus the
  importmap when the host defines `javascript_importmap_tags`.
- `flash[:notice]` and `flash[:alert]` rendered with `FlatPack::Alert`.
  OAuth, brands, embargo, features, library, messages, notifications, pages,
  publishable, stripe, support, and users set flash and rely on the layout
  to show it.

`FlatPack::SidebarLayout` is the application shell with a rail.
`FlatPack::PageLayout` is Flatpack's public page shell: a top bar, one
column, and a footer. The dummy `application` layout uses Sidebar Layout.
Put the page, including alerts, in the `main` slot. Gem screens that are
not inside those shells use `recording_studio/default_layout`.

The layout does not read `:body_theme`, `:seo_image`, or the removed page
nav slots (`:page_nav_back_url`, `:page_nav_back_label`,
`:page_nav_anchor_url`, `:page_nav_anchor_label`, `:page_nav_right`).

## Helper API

Recording Studio still provides:

- `default_layout_head { ... }`
- `recording_studio_seo_description(text)`

Page nav and page buttons are Flatpack helpers, available in every view:

- `content_for :title, "Workspaces"`
- `content_for :subtitle, "Choose a workspace."`
- `flat_pack_page_nav(back_href:, back_tooltip:, anchor_href:, anchor_tooltip:, ...)`
- `register_page_nav(label, href, role:, icon:)`

`flat_pack_page_nav` returns nil. The last call replaces the previous one.
With no block, the tag renders history back (or a back link when `back_href`
is set) and, when an anchor is present, a close control. A call with no
arguments still stores that history-back spec. `anchor_href` is also the
history back fallback. A block replaces that default row. A block does not
gain a close control when `return_to` fills a blank anchor. Omit the call,
and pass no `return_to`, and the icon side of the row is empty. Registered
page buttons still render, right-aligned, on that row.

`register_page_nav` returns nil. `role` is required: `:primary`,
`:secondary`, or `:destructive`. The layout places the group with
`render_page_nav(:top_nav)`. The view does not pass a CSS class or a button
style. Flatpack's top nav map paints `:primary` as a subtle button and
`:secondary` as a ghost button.

## Defaults

| Piece | Default |
| --- | --- |
| Title | `content_for(:title)` → `RecordingStudio.configuration.app_name` → `"CHANGE_APP_NAME_IN_DEFAULT_LAYOUT"` |
| Theme | `data-theme="rounded"` |
| Description | Omitted when blank |
| `og:title` | Same as `<title>` |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| Back | Shown when the view calls `flat_pack_page_nav`, including a call with no arguments (history back, icon `chevron-left`, Flatpack tooltip "Go back"). A registered spec uses that spec. With nothing registered and no valid `return_to`, the layout renders no icon row. |
| Anchor | Comes only from Flatpack: the view's `anchor_href`, or a valid `return_to` when the view left the anchor blank. Core adds no anchor of its own. The close icon is `x-mark`. The default tooltip is Flatpack's "Close". |
| Header | Rendered only when `content_for(:title)` is present. `FlatPack::PageTitle` uses that title and `content_for(:subtitle)` when the subtitle is present. |
| Page actions | Empty until the view calls `register_page_nav`. Then `render_page_nav(:top_nav)` renders on the nav row, right-aligned. Form submit and cancel stay in the form. |

## Page nav example

```erb
<% content_for :title, "Workspaces" %>
<% content_for :subtitle, "Choose a workspace." %>
<% flat_pack_page_nav(
  anchor_href: root_path,
  anchor_tooltip: "Home"
) %>
<% register_page_nav "Add workspace", new_workspace_path, role: :primary, icon: :plus %>
<% register_page_nav "Browse recordings", recordings_path, role: :secondary %>
```

Back and anchor together:

```erb
<% content_for :title, "New Workspace" %>
<% content_for :subtitle, "Create a container for recordings." %>
<% flat_pack_page_nav(
  back_href: workspaces_path,
  back_tooltip: "Workspaces",
  anchor_href: root_path,
  anchor_tooltip: "Home"
) %>
```

A later screen can carry the anchor forward. Flatpack appends it as
`return_to`, and the next page's `flat_pack_page_nav_tag` uses that value
when the view did not set `anchor_href`.

```erb
<%= render FlatPack::Button::Component.new(
  text: "Next",
  style: :primary,
  href: flat_pack_return_to_url(next_step_path)
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

Back and close copy come from Flatpack (`flatpack.page_nav.back` is "Go
back", `flatpack.page_nav.close` is "Close") unless the view passes
`back_tooltip` or `anchor_tooltip`. The gem no longer ships
`recording_studio.core.navigation.go_back` or `close`. The default layout
does not look up `recording_studio.core.navigation`.

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
