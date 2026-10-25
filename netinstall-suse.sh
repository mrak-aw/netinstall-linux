#!/usr/bin/env bash

LOG_FILE=/var/log/netinstall.log
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

PKGS=(
    # --- Утилиты ---
    git gh btop ddcutil brightnessctl playerctl fastfetch seatd fish jq bc flatpak
    # --- Разработка ---
    dotnet-sdk android-tools scrcpy
    # --- Виртуализация ---
    qemu qemu-ovmf-x86_64
    # --- Сеть и звук ---
    NetworkManager NetworkManager-applet throne
    pipewire pipewire-pulseaudio pipewire-alsa wireplumber
    # --- Bluetooth ---
    bluez bluez-auto-enable-devices
    # --- Hyprland ---
    hyprland hyprlock hyprshot hypridle awww waybar wofi polkit polkit-gnome xwayland matugen SwayNotificationCenter
    # --- Шрифты ---
    fontawesome-fonts google-noto-sans-fonts adwaita-fonts
    # --- Приложения ---
    vlc vlc-codecs ffmpeg
    helium-browser librewolf
    portprotonqt legacy-launcher
    dolphin pavucontrol-qt foot neovim kate Gapless obsidian localsend
    gwenview krita audacity inkscape keepassxc gnome-disk-utility filelight qbittorrent papers
    # --- Темы ---
    adw-gtk3 papirus-icon-theme nwg-look darkly qt5ct qt6ct
    # --- Порталы и Wayland ---
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    libqt5-qtwayland qt6-wayland typelib-1_0-Gtk-3_0
    wl-clipboard cliphist grim slurp satty swappy libnotify-tools
    kio-extras ffmpegthumbs
)

FLATPAKS=(
    io.github.kukuruzka165.materialgram
    com.vscodium.codium
)

EXTRA_GROUPS=(video render input audio kvm i2c)

FAILED=()
UNAVAILABLE=()   # пакеты, которых нет ни в одном репозитории

setup_all_repos() {
add_repo packman "https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/" 90

local OBS="https://download.opensuse.org/repositories"
add_repo obs-alternateved "${OBS}/home:/alternateved/openSUSE_Tumbleweed/"              # adw-gtk3
add_repo obs-dead-mozay   "${OBS}/home:/Dead_Mozay:/GNOME:/Apps/openSUSE_Tumbleweed/"   # gapless
add_repo obs-herbster0815 "${OBS}/home:/Herbster0815/openSUSE_Tumbleweed/"              # dotnet
add_repo obs-holiu0618    "${OBS}/home:/Holiu0618/openSUSE_Tumbleweed/"                 # darkly
add_repo obs-hardware     "${OBS}/hardware/openSUSE_Tumbleweed/"                        # scrcpy
add_repo obs-ackerman     "${OBS}/home:/ackerman/openSUSE_Tumbleweed/"                  # matugen / helium-browser / obsidian / localsend
add_repo legacy-launcher  "${OBS}/home:/tekidev/openSUSE_Tumbleweed/"                   # ch.tlaun.TL
add_repo_file throne      "https://parhelia512.github.io/throne-sle.repo"               # throne
add_repo_file librewolf   "https://repo.librewolf.net/librewolf.repo"                   # librewolf

zypper -n --gpg-auto-import-keys ref
}

# ============================================================
#  Вспомогательные функции
# ============================================================

log()  { echo "==> $*"; }
warn() { echo "!! $*"; }

# fail "сообщение" "метка для итогового списка"
fail() {
    warn "$1"
    FAILED+=("$2")
}

fix_selinux() {
    if command -v restorecon >/dev/null; then
        restorecon "$@"
    fi
}

unit_exists() {
    systemctl list-unit-files "$1" 2>/dev/null | grep -q "^$1"
}

# ============================================================
#  Подготовка
# ============================================================

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Запустите скрипт от root: sudo ./netinstall-suse.sh"
        exit 1
    fi
}

setup_logging() {
    exec > >(tee -ia "$LOG_FILE") 2>&1

    trap 'echo; warn "Скрипт прерван пользователем"; exit 130' INT TERM
}

detect_user() {
    USERNAME="${SUDO_USER:-}"

    if [[ -z $USERNAME || $USERNAME == root ]]; then
        USERNAME=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')
    fi

    if [[ -z $USERNAME ]] || ! id "$USERNAME" &>/dev/null; then
        echo "Ошибка: пользователь '$USERNAME' не существует!"
        exit 1
    fi

    USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    USER_GROUP=$(id -gn "$USERNAME")
}

check_environment() {
    if [[ ! -d $SCRIPT_DIR/.config ]]; then
        echo "Ошибка: рядом со скриптом нет папки .config ($SCRIPT_DIR/.config)"
        exit 1
    fi
}

# ============================================================
#  1. zypper
# ============================================================

configure_zypper() {
    local conf=/etc/zypp/zypp.conf

    mkdir -p /etc/zypp
    if [[ ! -f $conf ]]; then
        cp /usr/etc/zypp/zypp.conf "$conf" 2>/dev/null || echo '[main]' > "$conf"
    fi

    sed -i '/^solver.onlyRequires/d' "$conf"
    sed -i '0,/^\[main\]/s//[main]\nsolver.onlyRequires = true/' "$conf"

    fix_selinux "$conf"
}

# ============================================================
#  2. Репозитории
# ============================================================

# add_repo alias url [priority]
# Репозиторий добавляется, только если по URL есть repodata.
add_repo() {
    local alias=$1 url=$2 prio=${3:-110}

    if zypper lr "$alias" >/dev/null 2>&1; then
        log "Репозиторий $alias уже подключён, пропускаю"
        return 0
    fi

    if command -v curl >/dev/null \
        && ! curl -fsL --max-time 20 -o /dev/null "${url%/}/repodata/repomd.xml"; then
        fail "Репозиторий $alias недоступен ($url), пропускаю" "repo:$alias"
        return 1
    fi

    log "Подключение репозитория $alias"
    zypper -n ar -f -p "$prio" "$url" "$alias" \
        || fail "Не удалось добавить $alias, пропускаю" "repo:$alias"
}

# add_repo_file hint url
add_repo_file() {
    local hint=$1 url=$2 out rc

    if zypper lr | grep -qi "$hint"; then
        log "Репозиторий $hint уже подключён, пропускаю"
        return 0
    fi

    log "Подключение репозитория $hint ($url)"
    out=$(zypper -n ar -f "$url" 2>&1)
    rc=$?
    echo "$out"

    if (( rc != 0 )) && ! grep -qi "already exists" <<<"$out"; then
        fail "Не удалось добавить $hint, пропускаю" "repo:$hint"
    fi
}

# ============================================================
#  3. Обновление системы
# ============================================================

system_update() {
    zypper -n dup --allow-vendor-change
}

# ============================================================
#  4. Пакеты
# ============================================================

# Есть ли пакет (или capability) в подключённых репозиториях
pkg_provided() {
    zypper -n -q search -x --provides "$1" >/dev/null 2>&1
}

install_packages() {
    local p rc found
    local avail=()

    # Один неизвестный пакет заставляет `zypper in` (код 104) отменить ВСЮ установку,
    # поэтому сначала отсеиваем то, чего нет в репозиториях.
    log "Проверка наличия пакетов в репозиториях"
    found=$(zypper -n --xmlout search -x -t package "${PKGS[@]}" 2>/dev/null \
            | grep -oP '<solvable [^>]*\bname="\K[^"]+' | sort -u)

    for p in "${PKGS[@]}"; do
        if grep -qixF "$p" <<<"$found" || pkg_provided "$p"; then
            avail+=("$p")
        else
            UNAVAILABLE+=("$p")
            fail "Пакет $p не найден в репозиториях, пропускаю" "$p (нет в репозиториях)"
        fi
    done

    log "Установка пакетов (${#avail[@]} шт.)"
    zypper -n in --allow-vendor-change "${avail[@]}"
    rc=$?
    log "zypper in завершился с кодом $rc"

    if (( rc != 0 )); then
        warn "zypper in завершился с ошибкой (код $rc), смотрите лог: $LOG_FILE"
    fi

    if zypper lr packman >/dev/null 2>&1; then
        log "Переключение мультимедиа-пакетов на Packman"
        zypper -n dup --from packman --allow-vendor-change
    fi
}

verify_packages() {
    local installed p
    installed=$(rpm -qa --qf '%{NAME}\n')

    for p in "${PKGS[@]}"; do
        [[ " ${UNAVAILABLE[*]} " == *" $p "* ]] && continue
        grep -qixF "$p" <<<"$installed" \
            || rpm -q --whatprovides "$p" >/dev/null 2>&1 \
            || FAILED+=("$p (не установился)")
    done
}

install_flatpaks() {
    local app

    if ! command -v flatpak >/dev/null; then
        FAILED+=("flatpak (не установлен)")
        return
    fi

    log "Подключение Flathub"
    flatpak remote-add --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo \
        || FAILED+=("flathub (remote-add)")

    for app in "${FLATPAKS[@]}"; do
        flatpak install -y --noninteractive flathub "$app" \
            || FAILED+=("flatpak:$app")
    done
}

# ============================================================
#  5. Конфиги
# ============================================================

copy_configs() {
    local btusb="$SCRIPT_DIR/fixes/btusb-fix.conf"

    mkdir -p "$USER_HOME/.config"
    cp -rT "$SCRIPT_DIR/.config" "$USER_HOME/.config"
    chown -R "$USERNAME:$USER_GROUP" "$USER_HOME/.config"

    # В qt5ct/qt6ct путь к цветам зашит с чужим именем пользователя
    sed -i -E "s#/home/[^/]+/\.config#$USER_HOME/.config#g" \
        "$USER_HOME/.config/qt5ct/qt5ct.conf" "$USER_HOME/.config/qt6ct/qt6ct.conf" 2>/dev/null || true

    if [[ -f $btusb ]]; then
        install -Dm644 "$btusb" /etc/modprobe.d/btusb-fix.conf
    else
        fail "Нет файла $btusb, пропускаю" "btusb-fix.conf"
    fi

    # SELinux: правильные контексты для скопированных файлов
    if command -v restorecon >/dev/null; then
        restorecon -R "$USER_HOME/.config"
    fi
}

# ============================================================
#  6. Автологин в tty1
# ============================================================

setup_autologin() {
    local dir=/etc/systemd/system/getty@tty1.service.d

    mkdir -p "$dir"
    cat > "$dir/autologin.conf" <<EOT
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOT
}

# ============================================================
#  6.1 Автозапуск Hyprland на tty1 (один раз за загрузку)
# ============================================================

setup_hyprland_autostart() {
    local dir="$USER_HOME/.config/fish/conf.d"

    install -d -o "$USERNAME" -g "$USER_GROUP" "$dir"
    cat > "$dir/hyprland-autostart.fish" <<'EOT'
# Автозапуск Hyprland на tty1 (один раз за загрузку)
if status is-login
    and test (tty) = /dev/tty1
    and test -z "$WAYLAND_DISPLAY"
    and test -z "$DISPLAY"

    set -l flag /dev/shm/hyprland-autostart-(id -u)
    if not test -e $flag
        touch $flag
        if command -q start-hyprland
            exec start-hyprland
        else
            exec Hyprland
        end
    end
end
EOT
    chown "$USERNAME:$USER_GROUP" "$dir/hyprland-autostart.fish"
    fix_selinux "$dir/hyprland-autostart.fish"
}


# ============================================================
#  7. Группы и сервисы
# ============================================================

setup_i2c() {
    echo i2c-dev > /etc/modules-load.d/i2c-dev.conf
    modprobe i2c-dev 2>/dev/null || warn "Не удалось загрузить модуль i2c-dev"

    # Доступ к /dev/i2c-* для ddcutil без root (как на NixOS)
    getent group i2c >/dev/null || groupadd -r i2c
    cat > /etc/udev/rules.d/60-i2c-group.rules <<'EOT'
KERNEL=="i2c-[0-9]*", GROUP="i2c", MODE="0660"
EOT
    udevadm control --reload 2>/dev/null || true
    udevadm trigger --subsystem-match=i2c-dev 2>/dev/null || true
}

setup_groups() {
    local g
    for g in "${EXTRA_GROUPS[@]}"; do
        if getent group "$g" >/dev/null; then
            usermod -aG "$g" "$USERNAME"
        else
            log "Группы $g нет в системе, пропускаю"
        fi
    done
}

setup_lid() {
    install -d /etc/systemd/logind.conf.d
    cat > /etc/systemd/logind.conf.d/10-lid.conf <<'EOT'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
EOT
}

setup_services() {
    unit_exists seatd.service  && systemctl enable seatd
    unit_exists wicked.service && systemctl disable wicked
    systemctl enable NetworkManager

    [[ -x /usr/bin/fish ]] && chsh -s /usr/bin/fish "$USERNAME"
}

# ============================================================
#  Итог
# ============================================================

print_summary() {
    if ((${#FAILED[@]})); then
        echo
        warn "Не установлено / не подключено:"
        printf '   - %s\n' "${FAILED[@]}"
    fi

    echo "Готово. Перезагрузитесь: systemctl reboot"
}

# ============================================================
#  main
# ============================================================

main() {
    require_root
    setup_logging
    detect_user
    check_environment

    configure_zypper
    setup_all_repos
    system_update

    install_packages
    verify_packages
    install_flatpaks

    copy_configs
    setup_autologin
    setup_hyprland_autostart
    setup_i2c
    setup_groups
    setup_lid
    setup_services

    print_summary
}

main "$@"
