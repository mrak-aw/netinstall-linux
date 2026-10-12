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

# Папка, где лежит скрипт (там же должна лежать папка .config)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! id "$USERNAME" &>/dev/null; then
    echo "Ошибка: пользователь $USERNAME не существует!"
    exit 1
fi

if [[ ! -d "$SCRIPT_DIR/.config" ]]; then
    echo "Ошибка: рядом со скриптом нет папки .config ($SCRIPT_DIR/.config)"
    exit 1
fi

# ===== 1. Обновление системы =====
pacman -Syu --noconfirm

# ===== 2. Установка пакетов из официальных репозиториев =====
pacman -S --needed --noconfirm \
    base-devel sudo \
    git btop ddcutil brightnessctl playerctl fastfetch seatd fish jq bc \
    networkmanager network-manager-applet \
    pipewire pipewire-pulse pipewire-alsa wireplumber \
    hyprland hyprlock hyprpaper waybar wofi polkit swaync gtk3 \
    ttf-font-awesome noto-fonts adwaita-fonts \
    dolphin pavucontrol-qt foot neovim \
    adw-gtk-theme papirus-icon-theme nwg-look qt5ct qt6ct frameworkintegration \
    xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
    qt5-wayland qt6-wayland

# ===== 3. Пакеты из AUR (через yay) =====
# makepkg нельзя запускать от root, поэтому собираем от имени пользователя.
# На время установки даём ему sudo без пароля, потом сразу убираем.
echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-netinstall
chmod 440 /etc/sudoers.d/99-netinstall
trap 'rm -f /etc/sudoers.d/99-netinstall' EXIT

# Ставим yay, если его ещё нет
if ! command -v yay >/dev/null; then
    rm -rf /tmp/yay-bin
    sudo -H -u "$USERNAME" git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
    sudo -H -u "$USERNAME" bash -c 'cd /tmp/yay-bin && makepkg -si --noconfirm'
    rm -rf /tmp/yay-bin
fi

# Ставим по одному, чтобы ошибка с одним пакетом не остановила остальные
for p in waypaper gapless darkly-bin; do
    sudo -H -u "$USERNAME" yay -S --needed --noconfirm "$p" \
        || echo "!! Не удалось поставить $p из AUR"
done

rm -f /etc/sudoers.d/99-netinstall

# ===== 4. Копирование конфигов =====
mkdir -p /home/$USERNAME/.config
cp -rT "$SCRIPT_DIR/.config" /home/$USERNAME/.config
chown -R $USERNAME:$(id -gn $USERNAME) /home/$USERNAME/.config

# SELinux: правильные контексты для скопированных файлов
if command -v restorecon >/dev/null; then
    restorecon -R /home/$USERNAME/.config
fi

# ===== 5. Автологин в tty1 =====
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF

# ===== 6. Группы и сервисы =====
usermod -aG video,input $USERNAME
usermod -aG seat $USERNAME

systemctl enable seatd
systemctl enable NetworkManager

chsh -s /usr/bin/fish $USERNAME

echo "Готово. Перезагрузитесь: systemctl reboot"
