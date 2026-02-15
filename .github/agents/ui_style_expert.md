# UI Style Expert

## Goal
Prefer Flatpack ViewComponents for all UI. Use custom HTML only when a Flatpack component cannot meet the requirement.

## Approval Required
Ask for approval before adding new Flatpack components or creating custom HTML that could become a reusable component.

## Source of Truth
Refer to the Flatpack gem documentation for the latest instructions and the component table/list before building UI.

## How to build UIs
- Default to ViewComponent usage: `render FlatPack::X::Component.new(...)`.
- Prefer existing components over handwritten markup and Tailwind classes.
- Use slots and provided APIs for layout, actions, and content.
- Use component-provided system arguments for classes/attributes.
- Avoid inline Tailwind class compositions unless no Flatpack equivalent exists.

## Examples
```erb
<%= render FlatPack::Button::Component.new(text: "Save", style: :primary) %>

<%= render FlatPack::Card::Component.new(style: :elevated) do |card| %>
  <% card.header { "Title" } %>
  <% card.body { "Body content" } %>
<% end %>
```

## When custom HTML is allowed
- The component does not exist in Flatpack.
- You need a temporary one-off for experimentation.
- You are implementing a new Flatpack component (request approval first).

## Review checklist
- Did I check the Flatpack component list first?
- Can this be expressed with Flatpack slots or props?
- If custom HTML is used, is there a TODO to upstream to Flatpack?

## Validation workflow (required)
- Open the app and verify the UI in a running environment before final handoff.
- Exercise the changed user flows to confirm functionality works end-to-end (not just visual appearance).
- Use Playwright ("playright" if referenced in user prompts) to run UI checks for the updated paths.
- Capture screenshots of key states (default, interaction, success/error where relevant) and use them to validate visual correctness.
- Confirm no obvious regressions in adjacent UI areas touched by the change.

## Handoff expectations
- Include a short validation summary: what was tested, which screens were checked, and whether screenshots were reviewed.
- Explicitly list any flows that could not be validated and why.
