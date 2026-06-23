# Upgrading To 3.0.0

This guide covers the breaking changes between `2.0.0` and `3.0.0`: declaration-enforced recordable hierarchies and
capability-owned child recordables.

## Upgrade Impact

This is a breaking upgrade for:

- host apps with configured ActiveRecord recordable types that do not declare `recording_studio_recordable(...)`
- apps that previously treated child-only recordables as roots
- addons that own internal child recordables but do not register them through
  `RecordingStudio.register_capability(..., source:, child_recordables:)`

## What Changed

- Every configured ActiveRecord recordable type is expected to call `recording_studio_recordable(...)`.
- Declarations now define the type label, optional plural label, root eligibility, and declared parent types.
- `config.require_recordable_declarations` defaults to `true`; missing declarations raise
  `RecordingStudio::MissingRecordableDeclaration`.
- Capability-owned child recordables fail closed when undeclared, even if
  `config.require_recordable_declarations = false`.
- Non-root recordables must declare `allowed_parent_types:` unless their parent allowance is derived from an enabled
  capability.
- `RecordingStudio.root_recording_for(recordable)` only accepts recordables declared with `root: true`.
- New child recordings must have an allowed `parent_recording`; invalid parent/child combinations raise
  `RecordingStudio::InvalidParent` before the recordable is saved.
- Direct `RecordingStudio::Recording` saves also validate declaration rules, so bypassing `record!` does not create valid
  orphan recordings.
- Parent recordings with children are restricted from destruction by the `child_recordings` association.
- Type labels now prefer declaration `label:` and `plural_label:` before legacy label methods.

## Upgrade Steps

1. List every configured recordable type and any addon-owned child recordables.

```ruby
RecordingStudio.configure do |config|
  config.recordable_types = ["Workspace", "Page", "Comment"]
end
```

Inventory any addon-owned child recordables that should no longer be expressed as host-app-specific
`allowed_parent_types:` declarations.

2. Add `recording_studio_recordable` to every configured ActiveRecord model.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true
end

class Page < ApplicationRecord
  recording_studio_recordable label: "Page", root: false, allowed_parent_types: ["Workspace", "Page"]
end

class Comment < ApplicationRecord
  recording_studio_recordable label: "Comment", root: false, allowed_parent_types: ["Page"]
end
```

Keep `allowed_parent_types:` on domain recordables. Only omit it for addon-owned child recordables whose parents are
derived from capability enablement.

3. Keep root creation and child creation separate.

```ruby
workspace = Workspace.find_or_create_by!(name: "Studio")
root_recording = RecordingStudio.root_recording_for(workspace)

page_recording = root_recording.record(Page) do |page|
  page.title = "Getting started"
end

comment_recording = root_recording.record(Comment, parent_recording: page_recording) do |comment|
  comment.body = "Looks good"
end
```

Use `root_recording_for` only for declared roots. Use `root_recording.record(..., parent_recording: ...)` for child
recordables whose declarations use `root: false`.

4. If you ship addon-owned child recordables, register them with their capability.

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Host recordables should enable capabilities through mixins:

```ruby
class Page < ApplicationRecord
  include RecordingStudioAccessible::Accessible
end
```

The mixin should call `RecordingStudio.enable_capability(:accessible, on: name)`. Capability-owned child recordables
must still be declared and non-root, but they may derive parent allowance from enabled capabilities instead of a static
`allowed_parent_types:` list.

5. If you need a staged migration, temporarily disable strict missing-declaration enforcement.

```ruby
RecordingStudio.configure do |config|
  config.require_recordable_declarations = false
end
```

This only softens missing declarations into warnings. Invalid declarations and invalid hierarchy writes still raise.
It does not relax capability-owned child validation; undeclared capability children still fail closed.
Re-enable the default `true` setting after every configured type has a declaration.

6. Replace legacy type-label methods with declarations where practical.

```ruby
class Workspace < ApplicationRecord
  recording_studio_recordable label: "Workspace", plural_label: "Workspaces", root: true

  def recordable_name
    name
  end
end
```

`recordable_name` remains the preferred instance display-name hook. `recording_studio_label`,
`recordable_type_label`, and `recording_studio_type_label` remain compatibility fallbacks but are no longer the primary
type-label surface.

7. Run the focused validation tests for declaration, hierarchy, and capability-owned child behavior.

```bash
bundle exec ruby -Itest test/recordable_declarations_test.rb
bundle exec ruby -Itest test/capability_owned_recordables_test.rb
bundle exec ruby -Itest test/models/recording_api_methods_test.rb
bundle exec ruby -Itest test/dummy/test/models/commentable_capability_test.rb
```

## Common Upgrade Errors

| Error | Meaning | Fix |
| --- | --- | --- |
| `RecordingStudio::MissingRecordableDeclaration` | A configured ActiveRecord recordable type has no declaration. | Add `recording_studio_recordable(...)` to that model or temporarily set `require_recordable_declarations = false`. |
| `RecordingStudio::InvalidRecordableDeclaration` | A declaration is malformed, references an unregistered parent type, or leaves a non-root type without any valid parent allowance. | Register the parent type in `config.recordable_types`, ensure labels/root flags are valid, and declare `allowed_parent_types:` unless the type is capability-owned. |
| `RecordingStudio::RootNotAllowed` | A child-only recordable was used as a root. | Declare the type with `root: true` if it really is a root, or create it under an allowed parent recording. |
| `RecordingStudio::InvalidParent` | A child was recorded without a parent or under a disallowed parent type. | Pass `parent_recording:` and include that parent's recordable type in `allowed_parent_types:`. |
| `RecordingStudio::OrphanRecording` | A low-level new recording was attempted under an existing root without a parent. | Use `root_recording_for` for root creation or pass `parent_recording:` for child creation. |
| `ArgumentError` | A capability registration declared `child_recordables:` without `source:`. | Add `source:` when registering capability-owned child recordables. |

## Helpful Introspection

```ruby
RecordingStudio.validate_recordable_declarations!
RecordingStudio.recordable_declarations
RecordingStudio.root_recordable_types
RecordingStudio.root_recordable_declarations
RecordingStudio.declared_parent_types_for("Page")
RecordingStudio.declared_allowed_parent_types_for("Page")
RecordingStudio.capability_parent_types_for("Comment")
RecordingStudio.capability_allowed_parent_types_for("Comment")
RecordingStudio.recordable_parent_allowances_for("Comment")
RecordingStudio.allowed_parent_types_for("Page")
RecordingStudio.child_recordable_types_for("Page")
RecordingStudio.parent_capabilities_for(child_type: "Comment", parent_type: "Page")
RecordingStudio.parent_allowed?(child_type: "Page", parent_recording: root_recording)
```

Use these helpers in upgrade tests or console checks to confirm that the configured hierarchy matches the app's intended
recording tree.

## Addon Capability Migration

RecordingStudio `3.0.0` makes capability-owned child recordables a core contract. Addons that own internal child
recordables should register them with their capability instead of asking host apps to call implementation-specific child
APIs.

```ruby
RecordingStudio.register_capability(
  :accessible,
  RecordingStudioAccessible::RecordingMethods,
  source: "recording_studio_accessible",
  child_recordables: ["RecordingStudio::Access"]
)
```

Host recordables should enable capabilities through mixins:

```ruby
class Page < ApplicationRecord
  include RecordingStudioAccessible::Accessible
end
```

The mixin should call `RecordingStudio.enable_capability(:accessible, on: name)`. Core then derives the effective parent
allowance for `RecordingStudio::Access` under `Page`. Capability-owned child recordables must be registered, declared,
and non-root. `source:` is required when `child_recordables:` is present and is provenance metadata, not an authentication
boundary.

## Adopting the Shared Default Layout

RecordingStudio `3.0.0` ships a reusable layout for addon gems at
`app/views/layouts/recording_studio/default_layout.html.erb`. It provides a
`FlatPack::PageNav::Component` shell with standard Rails layout structure and
safe defaults. Addon controllers can opt in with a single concern include and
a lightweight helper API to configure page nav metadata.

> **Prerequisite:** The default layout depends on `FlatPack::PageNav::Component`
> and `FlatPack::Alert::Component`. These are bundled with RecordingStudio's
> FlatPack dependency — no additional gem installation is needed. The layout
> includes automatic fallbacks when FlatPack components are unavailable, so
> pages won't break if FlatPack hasn't been wired up yet.
>
> The demo route at `/layout_demo` in the dummy app shows a complete working
> example (see `test/dummy/app/controllers/layout_demo_controller.rb` and
> `test/dummy/app/views/layout_demo/show.html.erb`).

### What the Layout Provides

- `FlatPack::PageNav::Component` rendered at the top of every page.
- Direct page body rendering (no extra content wrapper).
- Standard `yield :head` support for metadata.
- Flash notice/alert rendering with `FlatPack::Alert::Component`.
- Automatic fallbacks when FlatPack components are unavailable.
- Safe defaults: no anchor action, empty right slot, title falls back to
  `RecordingStudio`.

### Opting In

**Step 1: Include the concern in your controller.**

```ruby
class WorkspacesController < ApplicationController
  include RecordingStudio::UsesDefaultLayout
end
```

This applies `layout "recording_studio/default_layout"` and makes
`RecordingStudio::LayoutHelper` available in your views.

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
  include RecordingStudio::LayoutHelper
end
```

**Step 2: Replace manual breadcrumb and page-chrome markup with the helper API.**

_Before (manual FlatPack breadcrumb and button slots):_

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

_After (PageNav with helper API):_

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

For a back-navigation pattern (e.g., a "New" form that navigates back to the
parent list), use the anchor slot as a styled back link:

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

You can use both sides simultaneously — the back button on the left and an
anchor or custom actions on the right — they are independent.

**Step 3: Remove any existing sidebar or custom layout that duplicates what
the default layout already provides.** The default layout is sidebar-free;
any addon-specific sidebar logic should live in addon layouts, not in the
shared default.

### Helper API Reference

| Method | Purpose |
| --- | --- |
| `recording_studio_page_nav(title:, **slots)` | Sets the page `<title>` and configures PageNav slots. |
| `recording_studio_page_nav_right { ... }` | Renders block content into the PageNav right slot. |
| `recording_studio_head { ... }` | Appends block content to the `<head>` element. |

### Supported Slot Keys

Pass any of these as keyword arguments to `recording_studio_page_nav`:

- `title` — Sets `<title>` and falls back to `"RecordingStudio"`.
- `page_nav_anchor_url` — URL for the anchor (close) button. Omit to hide.
- `page_nav_anchor_icon` — Icon for the anchor button (default: `"x-mark"`).
- `page_nav_anchor_label` — ARIA label for the anchor button (default: `"Close"`).
- `page_nav_back_icon` — Icon for the back button (default: `"chevron-left"`).
- `page_nav_back_label` — Label for the back button (default: `"Go back"`).
- `page_nav_back_style` — FlatPack button style for back (default: `"secondary"`).
- `page_nav_back_size` — FlatPack button size for back (default: `"md"`).

### Testing Your Layout Adoption

After adopting the default layout, verify your views render correctly:

```ruby
class WorkspacesControllerTest < ActionDispatch::IntegrationTest
  test "index renders default layout with page nav" do
    get workspaces_path, headers: modern_headers

    assert_response :success
    assert_select "title", text: "Workspaces"
    assert_select "body[data-recording-studio-default-layout='true']", count: 1
    assert_select "nav[aria-label='Page navigation']", count: 1
  end
end
```

The `data-recording-studio-default-layout="true"` attribute on `<body>` confirms
the layout is active. Assert on your specific nav links, titles, and right-slot
actions as needed.

### Before / After Summary

| Concern | Before (manual) | After (default layout) |
| --- | --- | --- |
| Layout source | Custom per-addon layout or no shared layout | `recording_studio/default_layout` |
| Page chrome | Manual `FlatPack::Breadcrumb::Component` | `FlatPack::PageNav::Component` (automatic) |
| Page nav config | `content_for` scattered across views | `recording_studio_page_nav(...)` helper |
| Right actions | Embedded in `PageTitle` actions slot | `recording_studio_page_nav_right { ... }` |
| Head metadata | Manual `content_for :head` | `recording_studio_head { ... }` |
| Flash messages | Per-view or per-layout | Rendered automatically by layout |

### Addon Author Notes

If you ship an addon gem with controllers, prefer
`include RecordingStudio::UsesDefaultLayout` over a custom layout. This ensures
a consistent page shell across all RecordingStudio addons and reduces
per-addon layout maintenance.

If your addon needs a sidebar, create a layout that inherits from or wraps
`recording_studio/default_layout` rather than duplicating the PageNav shell.

Full documentation is at `docs/layouts/default_layout.md`. A working demo is
available in the dummy app at `/layout_demo`.