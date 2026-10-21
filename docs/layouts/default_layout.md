# RecordingStudio Default Layout

`recording_studio/default_layout` is the shared, sidebar-free page shell for RecordingStudio addon gems.
The public layout file is a thin wrapper around
`app/views/recording_studio/shared/_default_layout.html.erb` so hosts keep a
stable layout name while the shell lives with other shared layout partials.
For TopNav-based show/new/edit flows, see `docs/layouts/action_layout.md`.

> **Prerequisite:** The layout depends on `FlatPack::PageNav::Component` and
> `FlatPack::Alert::Component`. These are bundled with RecordingStudio's
> FlatPack dependency — no extra gem install needed. The layout includes
> automatic fallbacks when FlatPack is unavailable, so pages won't break
> if FlatPack isn't wired up.

## What it provides

- `FlatPack::PageNav::Component` rendered at the top.
- Flash notice/alert rendering via `FlatPack::Alert::Component`.
- Direct page body rendering (the layout does not add an extra content wrapper).
- Standard Rails layout structure with `yield :head` support and optional `recording_studio/_default_layout_head` partial.
- SEO support: meta description, OpenGraph tags (og:title, og:type, og:url, og:description, og:image, og:site_name).
- Automatic fallbacks when FlatPack components are unavailable.
- Safe defaults when no page-nav metadata is provided.
- Configurable app name for title and OpenGraph fallback via `RecordingStudio.configuration.app_name`.

## Opting in from a controller

Call the class macro on the gem's base controller. Subclasses inherit it
through Rails layout inheritance, including when the parent already opted in.

```ruby
class ApplicationController < ActionController::Base
  recording_studio_layout { RecordingStudioX.configuration.layout }
end
```

The macro does three things:

- Stores the block. It is evaluated in the controller, with no arguments, on
  each request. Return that gem's layout setting.
- Defines `recording_studio_resolved_layout` and declares
  `layout :recording_studio_resolved_layout`.
- Adds `helper RecordingStudio::LayoutHelper`.

`recording_studio_layout` is available on `ActionController::Base` after the
engine loads. `RecordingStudio::ApplicationController` calls it with no block,
so core screens use the same lookup.

The macro replaces `RecordingStudio::UsesDefaultLayout`. Do not hard-code
`layout "recording_studio/default_layout"`.

## Choosing the layout

`recording_studio_resolved_layout` checks three levels. The first value that
is not `nil` wins.

1. The block's setting (the gem).
2. `RecordingStudio.configuration.layout` (the host, for every gem that falls
   through).
3. `RecordingStudio::DEFAULT_LAYOUT`, which is `"recording_studio/default_layout"`.

A setting at either of the first two levels may be:

| Setting | Result |
| --- | --- |
| String | That layout name. A blank string raises `ArgumentError`. |
| `false` | No layout. This does not fall through. |
| `nil` | Try the next level. |
| Callable | Invoked as `call(controller:)`. The return value uses the same three rules. |

```ruby
recording_studio_layout { RecordingStudioX.configuration.layout }
```

```ruby
RecordingStudio.configure do |config|
  config.layout = "application"
end
```

```ruby
RecordingStudio.configure do |config|
  config.layout = ->(controller:) { controller.action_name == "index" ? nil : false }
end
```

The callable takes the `controller:` keyword only. A positional parameter
raises `ArgumentError` with a message that names `controller:`. Returning
`nil` tries the next level. Returning `false` renders with no layout.

A controller-level declaration still wins over the inherited resolver:

```ruby
class PostsController < ApplicationController
  layout "recording_studio/action_layout"
end

class PreviewsController < ApplicationController
  layout false
end
```

`layout` with `only:` or `except:` is a normal Rails override and also wins.

To find hard-coded `layout "recording_studio/..."` calls, use
`RecordingStudio::Layout.hardcoded_layout_paths(root)` or
`rake recording_studio:check_layouts`. The rake task scans the host
`app/controllers` tree and exits non-zero when it finds one. Pass `ignore:`
to the Ruby method for a controller that intentionally selects the action
layout.

## Host layout contract

Gem views render Flatpack components and set `content_for` slots. They do not
render the application shell. Whatever layout the resolver picks has to
provide the surroundings below, or navigation, type, and flash messages
disappear.

`recording_studio/default_layout` is the reference page shell:

- **Slots.** `:head`, `:title`, `:body_theme`, `:seo_description`,
  `:seo_image`, the `page_nav_*` slots listed under Supported slot contract,
  and `:page_nav_right`.
- **Flatpack assets.** Stylesheets `flat_pack/variables` and
  `flat_pack/rich_text`, plus the importmap when the host defines
  `javascript_importmap_tags`. Gem views look unstyled without those
  stylesheets.
- **Alerts.** `flash[:notice]` and `flash[:alert]` rendered with
  `FlatPack::Alert::Component`.

Flatpack shells:

- `FlatPack::SidebarLayout::Component` is the application shell: sidebar,
  optional top nav, and main. The dummy `application` layout uses it. Put the
  page, including alerts, in the `main` slot.
- Flatpack does not ship a `PageLayout` component. The page shell is this
  default layout: PageNav, the alerts, and the slots above. A host that sets
  `configuration.layout` to its own layout should keep that page contract
  inside `SidebarLayout`'s main slot, or keep rendering
  `RecordingStudio::DEFAULT_LAYOUT` for gem screens.

## Supported slot contract

The layout reads optional `content_for` slots:

- `:head`
- `:title`
- `:body_theme`
- `:seo_description`
- `:seo_image`
- `:page_nav_anchor_url`
- `:page_nav_anchor_icon`
- `:page_nav_anchor_label`
- `:page_nav_back_icon`
- `:page_nav_back_label`
- `:page_nav_back_style`
- `:page_nav_back_size`
- `:page_nav_back_url`
- `:page_nav_right` (block content rendered into `PageNav` right slot)

## Helper API

Use helper methods instead of setting all slots manually:

- `recording_studio_page_nav(title: nil, **slot_values)`
- `recording_studio_page_nav_right { ... }`
- `default_layout_head { ... }`
- `recording_studio_seo_description(text)`
- `recording_studio_seo_image(url)`

## Defaults

If no nav config is provided:

| Slot | Default |
| --- | --- |
| Title | `content_for(:title)` → `RecordingStudio.configuration.app_name` → `"RecordingStudio"` |
| `body_theme` | `"rounded"` |
| `seo_description` | None (omitted when blank) |
| `seo_image` | None (omitted when blank) |
| `og:title` | Same as `<title>` |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| `page_nav_back_icon` | `"chevron-left"` |
| `page_nav_back_label` | `RecordingStudio.t("recording_studio.core.navigation.go_back")` → `"Go back"` (tooltip and accessible name) |
| `page_nav_back_style` | `:"secondary"` |
| `page_nav_back_size` | `:"md"` |
| `page_nav_back_url` | `nil` (back control is always shown; a URL becomes its `href`; with no URL, Flatpack uses history back and `page_nav_anchor_url` as `fallback_url`) |
| `page_nav_anchor_icon` | `"x-mark"` |
| `page_nav_anchor_label` | `RecordingStudio.t("recording_studio.core.navigation.close")` → `"Close"` (tooltip and accessible name) |
| Close action | Hidden unless `page_nav_anchor_url` is set. That URL is the close `href`. The layout does not read `params`. |
| Right slot | Empty. When set, `page_nav_right` renders in a trailing `ml-auto` row item. |
| Back action | Always rendered via `with_back`. |

## Migration Example

_Before — manual FlatPack breadcrumb and button slots:_

```erb
<% content_for :title, "Workspaces" %>

<%= render FlatPack::Breadcrumb::Component.new(class: "mb-4") do |breadcrumb| %>
  <% breadcrumb.item(text: "Home", href: root_path) %>
  <% breadcrumb.item(text: "Workspaces") %>
<% end %>

<%= render FlatPack::PageTitle::Component.new(
  title: "Workspaces",
  subtitle: "Choose a workspace."
) do |page_title| %>
  <% page_title.actions do %>
    <%= render FlatPack::Button::Component.new(
      text: "New Workspace", style: :primary, url: new_workspace_path
    ) %>
  <% end %>
<% end %>
```

_After — PageNav with helper API:_

```erb
<% recording_studio_page_nav(
  title: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_icon: "home",
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

<%= render FlatPack::PageTitle::Component.new(
  title: "Workspaces",
  subtitle: "Choose a workspace."
) %>
```

For a back-navigation form (e.g., "New Workspace"), use
`page_nav_back_url` to set the left-side back button:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_back_url: workspaces_path,
  page_nav_back_icon: "chevron-left",
  page_nav_back_label: "Workspaces"
) %>
```

Both sides are independent — you can combine the back button with an anchor
or custom right-slot actions on the same page:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_back_url: workspaces_path,
  page_nav_back_icon: "chevron-left",
  page_nav_back_label: "Workspaces",
  page_nav_anchor_url: root_path,
  page_nav_anchor_icon: "home",
  page_nav_anchor_label: "Home"
) %>
```

- **Back:** `page_nav_back_*` slots. The layout calls `with_back`. The label
  is the tooltip. `page_nav_back_url` is the href.
- **Close:** `page_nav_anchor_*` slots. The layout calls `with_close` only
  when `page_nav_anchor_url` is present. The label is the tooltip.
- **Trailing actions:** `recording_studio_page_nav_right` renders inside
  `with_item`, in a `ml-auto` wrapper, so those controls sit at the end of
  the row.

Both sides are independent — use the back button, the anchor, and the
right slot together on the same page if needed.

## SEO & OpenGraph

The default layout automatically renders OpenGraph `<meta>` tags in the `<head>`:

| Tag | Source |
| --- | --- |
| `og:title` | Same fallback chain as `<title>` |
| `og:type` | `"website"` |
| `og:url` | `request.original_url` |
| `og:description` | `content_for(:seo_description)` when present |
| `og:image` | `content_for(:seo_image)` when present |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| `<meta name="description">` | `content_for(:seo_description)` when present |

Set SEO metadata from views using helpers:

```erb
<% recording_studio_seo_description("Workspaces overview for your team") %>
<% recording_studio_seo_image("https://example.com/workspaces-og.png") %>
```

The `recording_studio_seo_description` call sets both the `<meta name="description">` tag and the `og:description`
tag from the same value.

### Configurable app name

Set a custom app name for the `<title>` and `og:site_name` fallbacks:

```ruby
# config/initializers/recording_studio.rb
RecordingStudio.configure do |config|
  config.app_name = "My App"
end
```

The title fallback chain is:

1. `content_for(:title)` — set per-view
2. `RecordingStudio.configuration.app_name` — configurable globally
3. `"RecordingStudio"` — final hardcoded default

### Optional `_head` partial

Sub-gems can provide `recording_studio/_default_layout_head.html.erb` in their view paths.
The layout automatically renders this partial when it exists (before `yield :head`), and silently
skips it when absent. This lets addons inject shared `<head>` content (meta tags, scripts, etc.)
without consumers needing to include it in every view.

## Testing

Verify your views render correctly after adopting the layout:

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

The `data-recording-studio-default-layout="true"` attribute on `<body>` confirms
the layout is active.

## Interface text

Static PageNav defaults and the fallback `aria-label` ship as English Rails I18n
keys under `recording_studio.core.navigation` in the gem's
`config/locales/en.yml`, looked up through `RecordingStudio.t` so a missing
locale falls back to the loaded `:en` translation (host English overrides
included) and finally the gem-shipped `en.yml` table — not a hand-copied Ruby
string. Hosts can override them. Callers that pass their own
`page_nav_back_label` / `page_nav_anchor_label` via `content_for` are unchanged.
The developer placeholder `CHANGE_APP_NAME_IN_DEFAULT_LAYOUT` is not
translated.

Empty Labels markers use `recording_studio.core.labels.empty` through
`RecordingStudio::Labels.empty_label` (see the Labels API).

## Addon Author Guidance

- Call `recording_studio_layout` on the gem base controller and return that
  gem's layout setting from the block. `nil` lets the host and then
  `RecordingStudio::DEFAULT_LAYOUT` decide.
- Do not hard-code `layout "recording_studio/default_layout"`. A screen that
  needs TopNav can declare `layout "recording_studio/action_layout"` on that
  controller only.
- If the addon needs a sidebar, wrap the page in `FlatPack::SidebarLayout`
  and keep the host layout contract. Do not duplicate the PageNav shell.
- Use `recording_studio_page_nav` in views for back/close and the page title.
