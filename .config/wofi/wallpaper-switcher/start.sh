#!/usr/bin/env bash

WALL_DIR="$HOME/Pictures/wallpapers"
WOFI_CONF="$HOME/.config/wofi/wallpaper-switcher/config"
WOFI_STYLE="$HOME/.config/wofi/wallpaper-switcher/style.css"

menu() {
    find -L "$WALL_DIR" -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        -printf '%P\n' | sort | while IFS= read -r rel; do
        echo "img:$WALL_DIR/$rel:text:$rel"
    done
}

selected=$(menu | wofi \
    --conf "$WOFI_CONF" \
    --style "$WOFI_STYLE" \
    --cache-file /dev/null \
    --sort-order=default)

selected=${selected##*text:}
[[ -n $selected && -f "$WALL_DIR/$selected" ]] || exit 0
path="$WALL_DIR/$selected"

# Если демон не запущен, стартуем и ждём его готовности (до ~3 секунд)
if ! awww query >/dev/null 2>&1; then
    setsid awww-daemon >/dev/null 2>&1 &
    for _ in {1..15}; do
        awww query >/dev/null 2>&1 && break
        sleep 0.2
    done
fi

awww img "$path" --transition-type fade --transition-duration 1

matugen image "$path" --source-color-index 0
