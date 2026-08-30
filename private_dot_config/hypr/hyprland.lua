-- Hyprland Lua configuration, managed by chezmoi.

----------------
-- Monitors
----------------

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.monitor({ output = "DP-3", mode = "highres", position = "0x0", scale = 1 })
hl.monitor({ output = "eDP-1", mode = "highres", position = "auto", scale = 1 })

----------------
-- Programs
----------------

-- Keep long-lived GUI applications in UWSM-managed app scopes.
local terminal = "uwsm app -- ghostty"
local fileManager = "uwsm app -- caja"
local menu = "hyprlauncher --toggle"
local browser = "uwsm app -- google-chrome-stable"
local screenshot = [[if pgrep -x -u "$UID" slurp >/dev/null; then pkill -x -u "$UID" slurp; else grim -g "$(slurp)" - | wl-copy; fi]]
local mainMod = "SUPER"
local bergAction = "/usr/bin/qs -c berg ipc call actions"

----------------
-- Autostart
----------------

hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -- hyprlauncher -d")
    hl.exec_cmd("uwsm app -- nm-applet")
    hl.exec_cmd("uwsm app -- /opt/1Password/1password --silent")
    hl.exec_cmd("uwsm app -- bitwarden-desktop")
    hl.exec_cmd("uwsm app -- tailscale systray")
end)

local bergReloadTimer = hl.timer(function()
    hl.exec_cmd("systemctl --user reload quickshell-berg.service")
end, { timeout = 1000, type = "oneshot" })

bergReloadTimer:set_enabled(false)

hl.on("monitor.added", function()
    bergReloadTimer:set_enabled(false)
    bergReloadTimer:set_enabled(true)
end)

----------------
-- Look and Feel
----------------

hl.config({
    ecosystem = {
        enforce_permissions = true,
        no_update_news = true,
        no_donation_nag = true,
    },
    general = {
        gaps_in = 5,
        gaps_out = 20,
        border_size = 2,
        col = {
            active_border = "rgba(5dc453ff)",
            inactive_border = "rgba(464646ee)",
        },
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        inactive_opacity = 1.0,
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },
    animations = {
        enabled = true,
    },
    dwindle = {
        preserve_split = true,
    },
    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
    },
})

hl.permission({ binary = "/usr/bin/grim", type = "screencopy", mode = "allow" })
hl.permission({ binary = "/usr/bin/hyprlock", type = "screencopy", mode = "allow" })
hl.permission({ binary = "/usr/lib/xdg-desktop-portal-hyprland", type = "screencopy", mode = "allow" })
hl.permission({ binary = "/usr/bin/hyprpm", type = "plugin", mode = "allow" })
hl.permission({ binary = "/usr/bin/hyprctl", type = "plugin", mode = "deny" })

hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.animation({ leaf = "windows", enabled = true, speed = 7, bezier = "myBezier" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 7, bezier = "default", style = "popin 80%" })
hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 8, bezier = "default" })
hl.animation({ leaf = "fade", enabled = true, speed = 7, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 6, bezier = "default" })

----------------
-- Input
----------------

hl.config({
    input = {
        kb_layout = "pl,us",
        kb_variant = ",intl",
        kb_model = "",
        kb_options = "grp:alt_shift_toggle",
        kb_rules = "",
        follow_mouse = 1,
        sensitivity = 0,
        touchpad = {
            natural_scroll = true,
            tap_to_click = true,
            clickfinger_behavior = true,
        },
    },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.device({ name = "logitech-pebble-mouse", natural_scroll = true })
hl.device({ name = "logitech-m350", natural_scroll = true })
hl.device({ name = "logitech-usb-receiver-consumer-control", natural_scroll = true })

----------------
-- Keybindings
----------------

hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + C", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("~/.config/hypr/session-exit.sh logout"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind("Print", hl.dsp.exec_cmd(screenshot))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("systemctl --user reload quickshell-berg.service"))

hl.bind(mainMod .. " + SHIFT + N", hl.dsp.window.move({ monitor = "+1" }))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.window.move({ workspace = "emptynm", follow = true }))

hl.bind(mainMod .. " + left", hl.dsp.focus({ workspace = "r-1" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ workspace = "r+1" }))

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(bergAction .. " volumeUp || wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(bergAction .. " volumeDown || wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(bergAction .. " toggleOutputMute || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd(bergAction .. " toggleInputMute || wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(bergAction .. " brightnessUp || brightnessctl s 10%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(bergAction .. " brightnessDown || brightnessctl s 10%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd(bergAction .. " mediaNext || playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd(bergAction .. " mediaPlayPause || playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd(bergAction .. " mediaPlayPause || playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd(bergAction .. " mediaPrevious || playerctl previous"), { locked = true })

----------------
-- Windows and Workspaces
----------------

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "xwayland-drag-fix",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})
