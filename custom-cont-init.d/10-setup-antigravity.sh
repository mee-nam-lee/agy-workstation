#!/usr/bin/with-contenv bash
set -e

echo "[custom-init] Configuring Antigravity 2.0, /dev/shm, Default Chrome Browser & Korean environment for user abc..."

# 0. Expand /dev/shm to 4GB to prevent Electron (Antigravity) + Chrome shared memory crashes (black screen)
mount -o remount,size=4G /dev/shm 2>/dev/null || true

# 1. Ensure /etc/nginx/sites-available/default listens on BOTH port 80 (Cloud Workstations) and 3000 (Qwiklabs)
if ! grep -q "listen 3000;" /etc/nginx/sites-available/default 2>/dev/null; then
    sed -i '/listen 80 default_server;/a \  listen 3000;' /etc/nginx/sites-available/default || true
fi

# 2. Fix KDE 6 qtpaths symlink & Google Chrome wrapper with --disable-dev-shm-usage
if [ -f /usr/bin/qtpaths6 ] && [ ! -e /usr/bin/qtpaths ]; then
    ln -sf /usr/bin/qtpaths6 /usr/bin/qtpaths
fi

cat << 'EOF' > /usr/bin/google-chrome-stable
#!/bin/bash
exec /usr/bin/google-chrome-stable.orig \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --disable-software-rasterizer \
  --ozone-platform=x11 \
  --password-store=basic \
  --no-first-run \
  --no-default-browser-check \
  "$@"
EOF
chmod +x /usr/bin/google-chrome-stable
ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome
ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium
ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium-browser
ln -sf /usr/bin/google-chrome-stable /usr/local/bin/wrapped-chromium

# 2b. Wrap /usr/local/bin/antigravity so it ALWAYS runs with --disable-dev-shm-usage
if [ -f /opt/antigravity/Antigravity-x64/antigravity ]; then
    rm -f /usr/local/bin/antigravity
    cat << 'EOF' > /usr/local/bin/antigravity
#!/bin/bash
exec /opt/antigravity/Antigravity-x64/antigravity \
  --no-sandbox \
  --disable-gpu \
  --disable-dev-shm-usage \
  --disable-software-rasterizer \
  --enable-logging=stderr \
  --ozone-platform=x11 \
  "$@"
EOF
    chmod +x /usr/local/bin/antigravity
fi

if [ -f /usr/share/applications/antigravity.desktop ]; then
    sed -i 's|Exec=.*|Exec=/usr/local/bin/antigravity %U|g' /usr/share/applications/antigravity.desktop || true
fi

# 3. Install direct xdg-open wrapper in /usr/local/bin supporting http/https/file/.html and preventing PATH recursion
cat << 'EOF' > /usr/local/bin/xdg-open
#!/bin/bash
TARGET="${1:-}"
case "$TARGET" in
  http://*|https://*|file://*|*.html|*.htm|*.svg|*.pdf)
    DISPLAY="${DISPLAY:-:1}" /usr/bin/google-chrome-stable "$TARGET" >/dev/null 2>&1 &
    exit 0
    ;;
  *)
    # If target is an existing file that ends in html or if opened as URL, open in Chrome; otherwise pass to system xdg-open with safe PATH
    PATH="/usr/bin:/bin:/usr/sbin:/sbin" exec /usr/bin/xdg-open "$@"
    ;;
esac
EOF
chmod +x /usr/local/bin/xdg-open

# 4. Configure KDE & XDG default browser (mimeapps.list & kdeglobals) for user abc
mkdir -p /config/.config /config/.local/share/applications
cat << 'EOF' > /config/.config/mimeapps.list
[Default Applications]
x-scheme-handler/http=google-chrome.desktop
x-scheme-handler/https=google-chrome.desktop
x-scheme-handler/about=google-chrome.desktop
x-scheme-handler/unknown=google-chrome.desktop
text/html=google-chrome.desktop
application/xhtml+xml=google-chrome.desktop
EOF
cp /config/.config/mimeapps.list /config/.local/share/applications/mimeapps.list

cat << 'EOF' > /config/.config/kdeglobals
[General]
BrowserApplication=google-chrome.desktop
EOF

# 5. Prepare Openbox/KDE autostart directory in /config
mkdir -p /config/.config/openbox
mkdir -p /config/.config/autostart
mkdir -p /config/Desktop

cat << 'EOF' > /config/.config/openbox/autostart
#!/usr/bin/env bash
export PATH="/usr/local/bin:$PATH"
export DISPLAY=:1
export WAYLAND_DISPLAY=wayland-0
export LANG=ko_KR.UTF-8
export LC_ALL=ko_KR.UTF-8
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export BROWSER=/usr/bin/google-chrome-stable

# Start fcitx5 Korean/English IME daemon in background if installed
if command -v fcitx5 >/dev/null 2>&1; then
    fcitx5 -d --replace 2>/dev/null || true
fi

# Wait briefly for Xwayland (:1) and KDE Plasma to settle, then launch Antigravity 2.0
sleep 2
if ! pgrep -f "/opt/antigravity" >/dev/null 2>&1; then
    PATH="/usr/local/bin:$PATH" BROWSER=/usr/bin/google-chrome-stable /usr/local/bin/antigravity >/config/antigravity.log 2>&1 &
fi
EOF
chmod +x /config/.config/openbox/autostart

mkdir -p /config/.config/labwc
cp /config/.config/openbox/autostart /config/.config/labwc/autostart
chmod +x /config/.config/labwc/autostart

# 6. Configure fcitx5 profile with Korean (Hangul) + English (US)
mkdir -p /config/.config/fcitx5
cat << 'EOF' > /config/.config/fcitx5/profile
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=hangul

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=hangul
Layout=

[GroupOrder]
0=Default
EOF

# 7. Place Desktop shortcuts for Antigravity, Chrome, Konsole (Terminal), and Dolphin (File Manager)
if [ -f /usr/share/applications/antigravity.desktop ]; then
    cp /usr/share/applications/antigravity.desktop /config/Desktop/antigravity.desktop
    chmod +x /config/Desktop/antigravity.desktop
fi
if [ -f /usr/share/applications/google-chrome.desktop ]; then
    cp /usr/share/applications/google-chrome.desktop /config/Desktop/google-chrome.desktop
    chmod +x /config/Desktop/google-chrome.desktop
fi
if [ -f /usr/share/applications/org.kde.konsole.desktop ]; then
    cp /usr/share/applications/org.kde.konsole.desktop /config/Desktop/org.kde.konsole.desktop
    chmod +x /config/Desktop/org.kde.konsole.desktop
else
    cat << 'EOF' > /config/Desktop/konsole.desktop
[Desktop Entry]
Type=Application
Name=Konsole
Comment=Terminal Emulator
Exec=konsole
Icon=utilities-terminal
Terminal=false
Categories=System;TerminalEmulator;
EOF
    chmod +x /config/Desktop/konsole.desktop
fi

if [ -f /usr/share/applications/org.kde.dolphin.desktop ]; then
    cp /usr/share/applications/org.kde.dolphin.desktop /config/Desktop/org.kde.dolphin.desktop
    chmod +x /config/Desktop/org.kde.dolphin.desktop
else
    cat << 'EOF' > /config/Desktop/dolphin.desktop
[Desktop Entry]
Type=Application
Name=Folder (Dolphin)
Comment=File Manager
Exec=dolphin /config
Icon=system-file-manager
Terminal=false
Categories=System;FileTools;FileManager;
EOF
    chmod +x /config/Desktop/dolphin.desktop
fi

chown -R abc:abc /config/.config /config/.local /config/Desktop
echo "[custom-init] Antigravity 2.0 & Default Browser setup complete."
