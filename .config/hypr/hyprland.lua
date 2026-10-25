-- ===== MONITORS =====
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

Apps = {
    terminal    = "foot",
    fileManager = "dolphin",
    browser     = "helium || librewolf",
    messenger   = "flatpak run io.github.kukuruzka165.materialgram",
    menu        = "pkill wofi || wofi --show drun",
    wallpaper   = "pkill wofi || ~/.config/wofi/wallpaper-switcher/start.sh",
}

require("colors")
require("rules")
require("binds")

-- ===== ENVIRONMENT VARIABLES =====
hl.env("LANG", "en_US.UTF-8")
hl.env("LC_MESSAGES", "en_US.UTF-8")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- ===== AUTOSTART =====
hl.on("hyprland.start", function()
hl.exec_cmd("awww-daemon")
hl.exec_cmd("waybar")
hl.exec_cmd("nm-applet")
hl.exec_cmd("hypridle")
hl.exec_cmd("wl-paste --type text --watch cliphist store")
hl.exec_cmd("wl-paste --type image --watch cliphist store")
hl.exec_cmd(Apps.terminal)
hl.exec_cmd("/usr/libexec/polkit-gnome-authentication-agent-1")
end)

-- ===== LOOK AND FEEL =====
hl.config({
    general = {
        gaps_in = 1,
        gaps_out = 1,
        border_size = 1,
        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
    decoration = {
        rounding = 8,
        rounding_power = 2,
        active_opacity = 1,
        shadow = { enabled = true, range = 20, offset = {0, 2}, render_power = 10, color = "rgba(00000020)" },
          blur   = { enabled = true, size = 3, passes = 4, vibrancy = 0.1696 },
    },
    animations = { enabled = 0 },

    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false
    },
})

hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1} } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1} } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1} } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.5, 0.5},   {0.75, 1} } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1} } })

hl.animation({ leaf = "global",     enabled = true, speed = 10,   bezier = "default" })
hl.animation({ leaf = "border",     enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows",    enabled = true, speed = 1.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 4.1,  bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear",       style = "popin 87%" })
hl.animation({ leaf = "fadeIn",     enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut",    enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers",     enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn",   enabled = true, speed = 4,    bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut",  enabled = true, speed = 1.5,  bezier = "linear",       style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces",    enabled = true, speed = 1.3, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn",  enabled = true, speed = 1.3, bezier = "almostLinear" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.3, bezier = "almostLinear" })

hl.config({
    master = { new_status = "master" },
    misc   = { force_default_wallpaper = -1, disable_hyprland_logo = false },
})

-- ===== INPUT =====
hl.config({
    input = {
        kb_layout    = "us,ru,ua",
        kb_options   = "grp:caps_toggle",
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad = { natural_scroll = true },
    },
    cursor = { no_warps = true },
})

hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })
