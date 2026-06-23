# RecordingStudio Default Layout

`recording_studio/default_layout` is the shared, sidebar-free page shell for RecordingStudio addon gems.

> **Prerequisite:** The layout depends on `FlatPack::PageNav::Component` and
> `FlatPack::Alert::Component`. These are bundled with RecordingStudio's
> FlatPack dependency — no extra gem install needed. The layout includes
> automatic fallbacks when FlatPack is unavailable, so pages won't break
> if FlatPack isn't wired up.

## What it provides

- `FlatPack::PageNav::Component` rendered at the top.
- Flash notice/alert rendering via `FlatPack::Alert::Component`.
- Direct page body rendering (the layout does not add an extra content wrapper).
- Standard Rails layout structure with `yield :head` support.
- Automatic fallbacks when FlatPack components are unavailable.
- Safe defaults when no page-nav metadata is provided.

## Opting in from a controller

Include the concern:

```ruby
include RecordingStudio::UsesDefaultLayout
```

This applies:

- `layout "recording_studio/default_layout"`
- `helper RecordingStudio::LayoutHelper`

> **Note:** `layout` replaces any previously declared layout for this
> controller. If your controller inherits from `ApplicationController`
> which sets `layout "application"`, including `UsesDefaultLayout` will
> override it. All actions in the controller will use
> `recording_studio/default_layout`.

To apply the layout only to specific actions:

```ruby
class WorkspacesController < ApplicationController
  include RecordingStudio::UsesDefaultLayout

  # Override per-action if some views still need the app layout
  layout "recording_studio/default_layout", only: [:index, :show]
  layout "application", only: [:settings]
end
```

Alternatively, skip the concern and set the layout + helper directly:

```ruby
class WorkspacesController < ApplicationController
  layout "recording_studio/default_layout"
  helper RecordingStudio::LayoutHelper
end
```

## Supported slot contract

The layout reads optional `content_for` slots:

- `:head`
- `:title`
- `:page_nav_anchor_url`
- `:page_nav_anchor_icon`
- `:page_nav_anchor_label`
- `:page_nav_back_icon`
- `:page_nav_back_label`
- `:page_nav_back_style`
- `:page_nav_back_size`
- `:page_nav_right` (block content rendered into `PageNav` right slot)

## Helper API

Use helper methods instead of setting all slots manually:

- `recording_studio_page_nav(title: nil, **slot_values)`
- `recording_studio_page_nav_right { ... }`
- `recording_studio_head { ... }`

## Defaults

If no nav config is provided:

| Slot | Default |
| --- | --- |
| Title | `"RecordingStudio"` |
| `page_nav_back_icon` | `"chevron-left"` |
| `page_nav_back_label` | `"Go back"` |
| `page_nav_back_style` | `:"secondary"` |
| `page_nav_back_size` | `:"md"` |
| `page_nav_anchor_icon` | `"x-mark"` |
| `page_nav_anchor_label` | `"Close"` |
| Anchor action | Hidden (no `page_nav_anchor_url` provided) |
| Right slot | Empty |

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

For a back-navigation form (e.g., "New Workspace"), repurpose the anchor slot
as a styled back link:

```erb
<% recording_studio_page_nav(
  title: "New Workspace",
  page_nav_anchor_url: workspaces_path,
  page_nav_anchor_icon: "chevron-left",
  page_nav_anchor_label: "Workspaces"
) %>
```

The PageNav has two independent positions:

- **Left side (back):** Configured via `page_nav_back_*` slots. Rendered
  automatically by `FlatPack::PageNav::Component`. Use this for the
  primary navigation action (e.g., browser-history back).
- **Right side (anchor + right slot):** Configured via `page_nav_anchor_*`
  slots and `recording_studio_page_nav_right`. The anchor button only
  appears when `page_nav_anchor_url` is set. Use the anchor for close,
  home, or a secondary navigation target.

Both sides are independent — use the back button, the anchor, and the
right slot together on the same page if needed.

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

## Addon Author Guidance

- Prefer `include RecordingStudio::UsesDefaultLayout` over a custom layout for
  consistent page chrome across all RecordingStudio addons.
- If your addon needs a sidebar, create a layout that wraps
  `recording_studio/default_layout` rather than duplicating the PageNav shell.
- Use `recording_studio_page_nav` in your views to configure back/close
  navigation and page titles — avoid setting `content_for` slots directly.
