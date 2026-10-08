# Roam window grouping

Roam's inbox and chat windows use the `roam` class. The Hyprland Lua config
combines mapped Roam windows into one locked tabbed group when a Roam window
opens and when the config reloads. The oldest Roam window anchors the group,
so new windows join its current workspace and monitor rather than a fixed one.
The `barred set lock` window rule keeps Roam out of unrelated focused groups.

- Super+Tab: next tab.
- Super+Shift+Tab: previous tab.
- Click a title in the group bar to select that tab.
- Existing workspace and monitor movement shortcuts move the whole group.

Requires the Hyprland Lua API and native `HL.Group:add` method (configured and
verified on Hyprland 0.56.2). No extra service or script is required.

## Verification

```bash
luac -p ~/.config/hypr/hyprland.lua
hyprctl reload
hyprctl configerrors
hyprctl -j clients | jq '[.[] | select(.class == "roam") | {title,workspace,monitor,grouped}]'
```

Both windows should list the same group addresses, workspace, and monitor.
Tab switching and moving to a temporary workspace and back were tested live.
Only one physical monitor was connected during verification.
`Hyprland --verify-config` segfaults on this workstation with both the original
and updated configs; live reload and `configerrors` were used for API checks.

## Rollback

Remove the `roam-tabs` rule, `groupRoamWindows` function, its event handlers, and
the two Tab bindings from `hyprland.lua`, then reload. To split the existing
Roam group after removing the automation, focus Roam and run:

```bash
hyprctl dispatch 'hl.dsp.group.toggle()'
```

Re-add and commit the reverted configuration through chezmoi.
