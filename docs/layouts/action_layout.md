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

Declare the layout on the controller that needs TopNav. That declaration
replaces an inherited `recording_studio_layout` resolver. The base controller
should still call the macro so other actions keep the shared lookup.
`RecordingStudio::LayoutHelper` comes from the macro; add it yourself only
when this controller does not inherit the macro.

```ruby
class PostsController < ApplicationController
  layout "recording_studio/action_layout"
  helper RecordingStudio::LayoutHelper
end
```

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

Static chrome on this partial (`Back` button text and the
`Action page navigation` aria-label) uses
`recording_studio.core.navigation` keys from the gem's English locale file,
looked up through `RecordingStudio.t` (missing locales fall back to the loaded
`:en` translation, then the gem-shipped `en.yml` table).
`title`, `items`, `resource`, and `context` stay caller-provided.

## Relationship to default layout

| Concern | Default layout | Action layout |
| --- | --- | --- |
| Chrome | `FlatPack::PageNav` | `FlatPack::TopNav` |
| Primary use | Index and most addon screens | Focused show/new/edit flows |
| SEO slots | `:title`, `:seo_description`, `:seo_image`, `:head` | Same |
| How to opt in | `recording_studio_layout` on the base controller | `layout "recording_studio/action_layout"` on that controller |

Public entrypoints live under `app/views/layouts/recording_studio/` and render
shared shells from `app/views/recording_studio/shared/`.
