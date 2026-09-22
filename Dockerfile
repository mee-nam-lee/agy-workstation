FROM us-docker.pkg.dev/qwiklabs-resources/lfs-images/vm-antigravity@sha256:c51f55bb6a90ce98c5da74a7869f748e4e18118b8deaf33d89dcf23dbe36dc9e

USER root
ENV DEBIAN_FRONTEND=noninteractive

# 1. Install Korean fonts, locales, and Fcitx5 Hangul IME
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    fonts-nanum \
    fonts-noto-cjk \
    fcitx5 \
    fcitx5-hangul \
    fcitx5-config-qt \
    fcitx5-frontend-gtk3 \
    fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt6 \
    dbus-x11 \
    xdg-utils \
    && sed -i '/ko_KR.UTF-8/s/^# //g' /etc/locale.gen \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen ko_KR.UTF-8 en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# 2. Update Google Antigravity 2.0 to latest version using the built-in updater script
RUN if [ -f /tmp/scripts/03-antigravity.sh ]; then \
        bash /tmp/scripts/03-antigravity.sh; \
    fi

# 3. Fix KDE 6 qtpaths & default browser symlinks (vm-antigravity purged /usr/bin/chromium which broke wrapped-chromium & xdg-open)
RUN ( [ -f /usr/bin/qtpaths6 ] && ln -sf /usr/bin/qtpaths6 /usr/bin/qtpaths || true ) && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium && \
    ln -sf /usr/bin/google-chrome-stable /usr/bin/chromium-browser && \
    ln -sf /usr/bin/google-chrome-stable /usr/local/bin/wrapped-chromium && \
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/google-chrome-stable 200 && \
    update-alternatives --set x-www-browser /usr/bin/google-chrome-stable && \
    update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/bin/google-chrome-stable 200 && \
    update-alternatives --set gnome-www-browser /usr/bin/google-chrome-stable

# 4. Configure Selkies Webtop Nginx to listen on port 80 (for Cloud Workstations gateway) AND port 3000
ENV CUSTOM_PORT=80
ENV CUSTOM_HTTPS_PORT=3001
ENV CUSTOM_WS_PORT=8082
ENV PIXELFLUX_WAYLAND=true
ENV SELKIES_ENCODER=x264enc,jpeg
ENV SELKIES_FILE_TRANSFERS=upload,download
ENV TITLE="Google Antigravity 2.0 (Selkies Webtop)"
ENV LANG=ko_KR.UTF-8
ENV LC_ALL=ko_KR.UTF-8
ENV GTK_IM_MODULE=fcitx
ENV QT_IM_MODULE=fcitx
ENV XMODIFIERS=@im=fcitx
ENV BROWSER=/usr/bin/google-chrome-stable

# 5. Add custom s6-overlay initialization script for Antigravity autostart & Korean IME profile
RUN mkdir -p /custom-cont-init.d
COPY custom-cont-init.d/10-setup-antigravity.sh /custom-cont-init.d/10-setup-antigravity.sh
RUN chmod +x /custom-cont-init.d/10-setup-antigravity.sh

EXPOSE 80 3000 3001
ENTRYPOINT ["/init"]
