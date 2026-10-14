#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root: sudo ./netinstall-suse.sh"
    exit 1
fi

# Определяем пользователя автоматически
USERNAME="${SUDO_USER:-}"

# Если запустили не через sudo (например, прямо из root), берём первого обычного пользователя
if [[ -z "$USERNAME" || "$USERNAME" == "root" ]]; then
    USERNAME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')"
fi

# Папка, где лежит скрипт
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$USERNAME" ]] || ! id "$USERNAME" &>/dev/null; then
    echo "Ошибка: пользователь '$USERNAME' не существует!"
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/.config" ]]; then
    echo "Ошибка: рядом со скриптом нет папки .config ($SCRIPT_DIR/.config)"
    exit 1
fi

# Сюда складывается всё, что не удалось поставить (выводится в конце)
FAILED=()

# ===== 1. Настройка zypper =====
mkdir -p /etc/zypp
[[ -f /etc/zypp/zypp.conf ]] || cp /usr/etc/zypp/zypp.conf /etc/zypp/zypp.conf
sed -i '/^solver.onlyRequires/d' /etc/zypp/zypp.conf
sed -i '0,/^\[main\]/s//[main]\nsolver.onlyRequires = false/' /etc/zypp/zypp.conf

# SELinux
if command -v restorecon >/dev/null; then
    restorecon /etc/zypp/zypp.conf
fi

# ===== 2. Репозитории =====
# Репозиторий добавляется, только если по URL есть repodata
add_repo() {
    local alias="$1" url="$2" prio="${3:-110}"
    if zypper lr "$alias" >/dev/null 2>&1; then
        echo "==> Репозиторий $alias уже подключён, пропускаю"
        return 0
    fi
    if ! curl -fsI --max-time 15 "${url%/}/repodata/repomd.xml" >/dev/null; then
        echo "!! Репозиторий $alias недоступен ($url), пропускаю"
        FAILED+=("repo:$alias")
        return 1
    fi
    echo "==> Подключение репозитория $alias"
    zypper -n ar -f -p "$prio" "$url" "$alias" \
        || echo "!! Не удалось добавить $alias, пропускаю"
}

add_repo packman "https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/" 90

OBS="https://download.opensuse.org/repositories"
add_repo obs-alternateved "${OBS}/home:/alternateved/openSUSE_Tumbleweed/"   # adw-gtk3
add_repo obs-dead-mozay   "${OBS}/home:/Dead_Mozay:/GNOME:/Apps/openSUSE_Tumbleweed/"   # gapless
add_repo obs-Herbster0815 "${OBS}/home:/Herbster0815/openSUSE_Tumbleweed/"   # dotnet
add_repo obs-holiu0618    "${OBS}/home:/Holiu0618/openSUSE_Tumbleweed/"   # darkly
add_repo obs-hardware     "${OBS}/hardware/openSUSE_Tumbleweed/"   # scrcpy

zypper -n --gpg-auto-import-keys ref

# ===== 3. Обновление системы =====
zypper -n dup --allow-vendor-change
zypper -n dup --from packman --allow-vendor-change

# ===== 4. Установка пакетов =====
PKGS=(
    # --- Утилиты ---
    git gh btop ddcutil brightnessctl playerctl fastfetch seatd fish jq bc
    # --- Разработка ---
    dotnet-sdk-8.0 android-tools scrcpy
    # --- Виртуализация ---
    qemu qemu-ovmf-x86_64
    # --- Сеть и звук ---
    NetworkManager NetworkManager-applet
    pipewire pipewire-pulseaudio pipewire-alsa wireplumber
    # --- Hyprland ---
    hyprland hyprlock hyprpaper waybar wofi polkit SwayNotificationCenter
    # --- Шрифты ---
    fontawesome-fonts google-noto-sans-fonts adwaita-fonts
    # --- Приложения ---
    dolphin pavucontrol-qt foot neovim Gapless
    vlc vlc-codecs ffmpeg
    pinta krita audacity FreeCAD inkscape keepassxc gnome-disk-utility filelight
    portprotonqt
    # --- Темы ---
    adw-gtk3 papirus-icon-theme nwg-look darkly qt5ct qt6ct
    # --- Порталы и Wayland ---
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
    libqt5-qtwayland qt6-wayland
)

# Пакеты, которых, вероятно, нет в репозиториях (нужен отдельный OBS-репозиторий)
UNVERIFIED_PKGS=(

)

zypper -n in --allow-vendor-change "${PKGS[@]}"
zypper -n in --allow-vendor-change "${UNVERIFIED_PKGS[@]}"

# Проверка: что из списка реально установилось (имя без учёта регистра)
INSTALLED_NAMES="$(rpm -qa --qf '%{NAME}\n')"
for p in "${PKGS[@]}" "${UNVERIFIED_PKGS[@]}"; do
    grep -qixF "$p" <<<"$INSTALLED_NAMES" \
        || rpm -q --whatprovides "$p" >/dev/null 2>&1 \
        || FAILED+=("$p")
done

# ===== 5. Копирование конфигов =====
mkdir -p /home/$USERNAME/.config
cp -rT "$SCRIPT_DIR/.config" /home/$USERNAME/.config
chown -R $USERNAME:$(id -gn $USERNAME) /home/$USERNAME/.config

# SELinux: правильные контексты для скопированных файлов
if command -v restorecon >/dev/null; then
    restorecon -R /home/$USERNAME/.config
fi

# ===== 6. Автологин в tty1 =====
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOT
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOT

# ===== 7. Группы и сервисы =====
usermod -aG video,input $USERNAME
usermod -aG seat $USERNAME
getent group kvm >/dev/null && usermod -aG kvm $USERNAME

systemctl enable seatd
systemctl disable wicked
systemctl enable NetworkManager

chsh -s /usr/bin/fish $USERNAME

# ===== Итог =====
if ((${#FAILED[@]})); then
    echo
    echo "!! Не установлено / не подключено:"
    printf '   - %s\n' "${FAILED[@]}"
fi

echo "Готово. Перезагрузитесь: systemctl reboot"
