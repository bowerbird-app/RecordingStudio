# RecordingStudio Default Layout

`recording_studio/default_layout` is the shared page shell. It does not
assume a sidebar or a page kind. The public layout file wraps
`app/views/recording_studio/shared/_default_layout.html.erb`.

The shell is `FlatPack::PageLayout` (`width: :default`). Nothing else wraps
that component. `top_nav_width` stays `:content` and `content_scroll` stays
`:below`, so the bar matches the column and sits above the title. When the
view sets back, close, or page actions, the layout draws one
`FlatPack::TopNav` with `padding: :none`. Back and close sit on the left as
two round buttons. Page actions sit on the right.

> **Prerequisite:** `flat_pack` >= 0.1.310 is required. The layout renders
> Flatpack components directly. `flat_pack` is not on RubyGems. The gemspec
> declares the dependency, and the host Gemfile supplies the git source
> (`https://github.com/bowerbird-app/flatpack.git`, tag `v0.1.310`).

## What it provides

- Back and close from `flat_pack_page_nav(round: true)` /
  `flat_pack_page_nav_tag`. They are two round buttons, not a group or a card.
- One `page_nav_button_group` (`variant: :outlined`, ghost `sm` for every
  role, `collapse: :menu`) for `register_page_nav` entries. An empty bucket
  renders nothing. Outlined does not restyle the children, so primary stays
  ghost, the same as the other roles.
- `TopNav` does not fold. Below 768px the button group is the only phone
  menu. Back and close stay visible. Omit `menu_label`, so the trigger is
  the bars glyph.
- Flash notice and alert via `FlatPack::Alert::Component`.
- `FlatPack::PageTitle` from `:title` and `:subtitle`.
- The page body via `yield`.
- `<title>`, optional description, and OpenGraph title, type, url,
  description, and site name.
- `yield :head`, and `recording_studio/_default_layout_head` when that
  partial is on the view path.
- Stylesheets `flat_pack/variables`, `flat_pack/application`, and
  `flat_pack/rich_text`, plus the importmap when the host defines
  `javascript_importmap_tags`.
- `data-theme="rounded"` on `<html>`.
- Document title and site-name fallback from
  `RecordingStudio.configuration.app_name`.

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
block, so core screens use the same lookup.

Do not hard-code `layout "recording_studio/default_layout"`.
`RecordingStudio::Layout.hardcoded_layout_paths(root)` and
`rake recording_studio:check_layouts` report those calls.

## Gem adoption

One setting per surface, defaulting to `nil`. Each surface has its own base
controller and its own block. A `nil` setting lets the host's core layout,
then `RecordingStudio::DEFAULT_LAYOUT`, decide.

```ruby
module Library
  class ApplicationController < ActionController::Base
    recording_studio_layout { RecordingStudioLibrary.configuration.library_layout }
  end
end
```

## Hosts

Set the core default for every gem whose block returns `nil`:

```ruby
RecordingStudio.configure do |config|
  config.layout = "application"
  config.app_name = "My App"
end
```

A callable is invoked as `call(controller:)`.

The dummy app loads Flatpack the way the install generator does: Tailwind
`@source` globs for Flatpack components and helpers, stylesheets
`flat_pack/variables`, `flat_pack/application`, and `flat_pack/rich_text`,
and the Flatpack importmap pins. Do not fork `--color-fp-*` in the host
Tailwind file. Re-set kit radii on unlayered `:root` so Tailwind's
`--radius-md` default does not win.

## Host layout contract

Gem views set `content_for` slots and call Flatpack page-nav helpers. They
do not draw the shell. A host layout that replaces the default has to
provide the same surroundings.

| Slot | How views set it | What the layout does |
| --- | --- | --- |
| `:title` | `content_for :title` | Document `<title>`, `og:title`, and `FlatPack::PageTitle` |
| `:subtitle` | `content_for :subtitle` | Page title subtitle |
| `:head` | `default_layout_head` or `content_for :head` | Rendered in `<head>` |
| `:seo_description` | `recording_studio_seo_description` | Description and `og:description` |

Page chrome is not a `content_for` slot:

- `flat_pack_page_nav(...)` in the view. `flat_pack_page_nav_tag` in the layout.
- `register_page_nav "Label", path, role: :primary|:secondary|:destructive`.
  The layout calls `page_nav_button_group` once.

The view renders before the layout, so registrations and `content_for` are
already stored when the layout reads them.

Also required:

- Stylesheets `flat_pack/variables`, `flat_pack/application`, and
  `flat_pack/rich_text`, plus the importmap.
- `flash[:notice]` and `flash[:alert]` rendered with
  `FlatPack::Alert::Component`.

`FlatPack::SidebarLayout` is the application shell when a host wants a
sidebar. This default layout is the page shell without one.

## Helper API

Recording Studio still provides:

- `default_layout_head { ... }`
- `recording_studio_seo_description(text)`

Flatpack provides the page nav:

- `flat_pack_page_nav(round: true, back_href:, back_tooltip:, anchor_href:, anchor_tooltip:)`
- `register_page_nav "Label", path, role:, icon:, overflow:`
- `page_nav_button_group(styles:, variant:, collapse:)` — the layout calls this

`recording_studio_page_nav` and `recording_studio_page_nav_right` are removed.

## Defaults

| Piece | Default |
| --- | --- |
| Document title | `content_for(:title)` → `RecordingStudio.configuration.app_name` → `"CHANGE_APP_NAME_IN_DEFAULT_LAYOUT"` |
| Visible title | `FlatPack::PageTitle` when `:title` is present. `:subtitle` is optional. |
| Theme | `data-theme="rounded"` |
| Description | Omitted when blank |
| `og:title` | Same as `<title>` |
| `og:site_name` | `RecordingStudio.configuration.app_name` → page title |
| Back and close | Whatever `flat_pack_page_nav` stored. No call and no `return_to` means no row. Flatpack's own labels apply unless the view passes a tooltip. |
| Page actions | One button group when the default bucket has entries. `overflow: true` parks that entry in the group's More menu. The phone menu lists every entry once. |

## Example

```erb
<% content_for :title, "Field notes" %>
<% content_for :subtitle, "Packing list for the next shoot." %>
<% flat_pack_page_nav(round: true, anchor_href: root_path, anchor_tooltip: "Home") %>
<% register_page_nav "New page", new_page_path, role: :primary, icon: :plus %>
<% register_page_nav "Share", share_page_path, role: :secondary %>
<% register_page_nav "Delete", page_path, role: :destructive, icon: :trash, overflow: true %>
```

Back link and close together:

```erb
<% content_for :title, "New workspace" %>
<% flat_pack_page_nav(round: true,
  back_href: workspaces_path,
  back_tooltip: "Workspaces",
  anchor_href: root_path,
  anchor_tooltip: "Home"
) %>
```

A screen with no `register_page_nav` shows the back row only. The layout
does not render an empty button group.

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

A gem can ship `app/views/recording_studio/_default_layout_head.html.erb`.
The layout renders it before `yield :head` when the partial is found.

## Interface text

Back and close copy come from Flatpack unless the view passes `back_tooltip`
or `anchor_tooltip`. The layout does not read
`recording_studio.core.navigation`.

The developer placeholder `CHANGE_APP_NAME_IN_DEFAULT_LAYOUT` is not
translated. It is the document title only. It is not a visible page heading.

## Testing

```ruby
get workspace_path(workspace)

assert_select "header nav[aria-label='Page navigation']", count: 1
assert_select "header .fp-button-group-menu__row a", text: "New Page", count: 1
assert_select "header .fp-button-group-menu[data-controller='flat-pack--button-group-menu']", count: 1
```

`data-recording-studio-default-layout="true"` on `<body>` confirms the
layout is active. `collapse: :menu` keeps each action in the wide row and
again in the phone panel. Assert each place once, and assert the group is
not repeated in `<main>`.
