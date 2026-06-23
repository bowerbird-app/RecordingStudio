# RecordingStudio Action Layout

`recording_studio/action_layout` is an optional TopNav shell for focused
create/show/edit flows. Prefer `recording_studio/default_layout` (PageNav) for
most addon screens; use this layout when a page needs left/center/right TopNav
regions instead of PageNav.

> **Prerequisite:** The layout depends on `FlatPack::TopNav::Component` and
> `FlatPack::Alert::Component`.

## What it provides

- `FlatPack::TopNav::Component` with optional `:top_nav_left`, `:top_nav_center`,
  and `:top_nav_right` content.
- Flash notice/alert rendering via `FlatPack::Alert::Component`.
- The same SEO / OpenGraph contract as the default layout
  (`:title`, `:seo_description`, `:seo_image`, `:head`).
- Optional `:before_body_end` content.
- Shared stylesheet, icon, and importmap wiring with the default layout.

## Opting in from a controller

```ruby
class PostsController < ApplicationController
  layout "recording_studio/action_layout"
  helper RecordingStudio::LayoutHelper
end
```

Use `RecordingStudio::LayoutHelper` for SEO helpers. There is no separate
action-layout concern; set the layout explicitly when you need TopNav.

## Supported slots

- `:head`
- `:title`
- `:body_theme`
- `:seo_description`
- `:seo_image`
- `:top_nav_left`
- `:top_nav_center`
- `:top_nav_right`
- `:before_body_end`

## Page nav partial

For the left TopNav region, render the shared page-nav partial with explicit
locals:

```erb
<% content_for :top_nav_left do %>
  <%= render "recording_studio/shared/page_nav",
        title: "Post",
        back_path: posts_path,
        items: [{ label: "Overview", href: post_path(@post) }],
        resource: "Post",
        context: "Workspace A" %>
<% end %>
```

Locals: `title`, `back_path`, `items`, `resource`, `context`. No hidden
instance variables are required.

## Relationship to default layout

| Concern | Default layout | Action layout |
| --- | --- | --- |
| Chrome | `FlatPack::PageNav` | `FlatPack::TopNav` |
| Primary use | Index and most addon screens | Focused show/new/edit flows |
| SEO slots | `:title`, `:seo_description`, `:seo_image`, `:head` | Same |
| Helper concern | `UsesDefaultLayout` | Set `layout` + `helper` explicitly |

Public entrypoints live under `app/views/layouts/recording_studio/` and render
shared shells from `app/views/recording_studio/shared/`.
