# Roam window grouping

Roam's inbox and chat windows use the `roam` class. The Hyprland Lua config
combines mapped Roam windows into one locked tabbed group when a Roam window
opens, its class changes, and when the config starts or reloads. Grouping is
debounced by 150 ms so XWayland mapping and static group rules finish first. The oldest Roam window anchors the group,
so new windows join its current workspace and monitor rather than a fixed one.
The `barred set lock` window rule keeps Roam out of unrelated focused groups.
The merger detaches extra windows from their initial singleton groups and
briefly unlocks the destination before adding tabs, then relocks it and restores
the previously focused window. Native group additions refuse locked groups.

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
The startup fix was also verified by mapping temporary X11 windows with the
Roam class, including setting the class after mapping; they joined the existing
Roam group without a config reload.
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
