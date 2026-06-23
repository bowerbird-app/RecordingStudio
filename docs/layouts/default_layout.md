# RecordingStudio Default Layout

`recording_studio/default_layout` is the shared, sidebar-free page shell for RecordingStudio addon gems.

## What it provides

- `FlatPack::PageNav::Component` rendered at the top.
- Direct page body rendering (the layout does not add an extra content wrapper).
- Standard Rails layout structure with `yield :head` support.
- Safe defaults when no page-nav metadata is provided.

## Opting in from a controller

Include the concern:

```ruby
include RecordingStudio::UsesDefaultLayout
```

This applies:

- `layout "recording_studio/default_layout"`
- `helper RecordingStudio::LayoutHelper`

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

- Back button uses FlatPack defaults.
- Anchor action is hidden.
- Right slot is empty.
- Title falls back to `RecordingStudio`.

## Demo reference

See dummy app route `/layout_demo` for a working example that sets:

- head metadata
- title
- optional anchor action
- optional right-side action
