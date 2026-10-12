#!/usr/bin/env bash

# Определяем пользователя автоматически
USERNAME="${SUDO_USER:-}"

# Если запустили не через sudo (например, прямо из root), берём первого обычного пользователя
if [[ -z "$USERNAME" || "$USERNAME" == "root" ]]; then
    USERNAME="$(getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 {print $1; exit}')"
fi
if [[ $EUID -ne 0 ]]; then
    echo "Запустите скрипт от root: sudo ./netinstall-arch.sh"
    exit 1
fi

# Папка, где лежит скрипт
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! id "$USERNAME" &>/dev/null; then
    echo "Ошибка: пользователь $USERNAME не существует!"
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/.config" ]]; then
    echo "Ошибка: рядом со скриптом нет папки .config ($SCRIPT_DIR/.config)"
    exit 1
fi

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
add_repo() {
    local alias="$1" url="$2" prio="${3:-110}"
    if zypper lr "$alias" >/dev/null 2>&1; then
        echo "==> Репозиторий $alias уже подключён, пропускаю"
        return 0
    fi
    echo "==> Подключение репозитория $alias"
    zypper -n ar -f -p "$prio" "$url" "$alias" \
        || echo "!! Не удалось добавить $alias, пропускаю"
}

add_repo packman "https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/" 90

OBS="https://download.opensuse.org/repositories"
add_repo obs-alternateved "${OBS}/home:/alternateved/openSUSE_Tumbleweed/" #adw-gtk3
add_repo obs-dead-mozay   "${OBS}/home:/Dead_Mozay:/GNOME:/Apps/openSUSE_Tumbleweed/" #gapless
add_repo obs-holiu0618    "${OBS}/home:/Herbster0815/openSUSE_Tumbleweed/x86_64" # dotnet
add_repo obs-holiu0618    "${OBS}/home:/Holiu0618/openSUSE_Tumbleweed/" # darkly

zypper -n --gpg-auto-import-keys ref

# ===== 3. Обновление системы =====
zypper -n dup --allow-vendor-change
zypper -n dup --from packman --allow-vendor-change

# ===== 4. Установка пакетов =====
zypper -n in --allow-vendor-change \
    # System
    git gh btop ddcutil brightnessctl scrcpy dotnet android-tools ffmpeg qemu ovmf playerctl fastfetch seatd fish jq bc \
    # Network
    NetworkManager NetworkManager-applet \
    # Audio
    pipewire pipewire-pulseaudio pipewire-alsa wireplumber \
    # DE
    hyprland hyprlock hyprpaper waybar waypaper wofi polkit SwayNotificationCenter \
    # Шрифты
    fontawesome-fonts google-noto-sans-fonts adwaita-fonts \
    # Приложения
    dolphin pavucontrol-qt foot neovim Gapless vlc pinta krita audacity onlyoffice-desktop-editors FreeCAD inkscape keepassxc anki gnome-disk-utility filelight portprotonqt \
    # Оформление и темы
    adw-gtk3 papirus-icon-theme nwg-look darkly qt5ct qt6ct \
    # Порталы рабочего стола и системные утилиты
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    libqt5-qtwayland qt6-wayland


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
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

# ===== 7. Группы и сервисы =====
usermod -aG video,input $USERNAME
usermod -aG seat $USERNAME

systemctl enable seatd
systemctl disable wicked
systemctl enable NetworkManager

chsh -s /usr/bin/fish $USERNAME

echo "Готово. Перезагрузитесь: systemctl reboot"
