#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/tmp/ddc-brightness"
DELTA_FILE="${STATE_DIR}/delta"
PID_FILE="${STATE_DIR}/pid"
DEBOUNCE=0.2   # секунды тишины перед применением

mkdir -p "$STATE_DIR"
step="$1"   # ожидается число, например 20 или -20

# накапливаем суммарное изменение
current=$(cat "$DELTA_FILE" 2>/dev/null || echo 0)
echo $((current + step)) > "$DELTA_FILE"

# отменяем предыдущий отложенный apply, если он ещё ждёт
if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
fi

# запускаем новый отложенный apply
(
    sleep "$DEBOUNCE"
    delta=$(cat "$DELTA_FILE" 2>/dev/null || echo 0)
    echo 0 > "$DELTA_FILE"

    if (( delta != 0 )); then
        if (( delta > 0 )); then
            ddcutil setvcp 10 + "$delta" >/dev/null 2>&1
        else
            ddcutil setvcp 10 - "${delta#-}" >/dev/null 2>&1
        fi
    fi

    pkill -RTMIN+8 waybar 2>/dev/null || true
    rm -f "$PID_FILE"
) &
echo $! > "$PID_FILE"
