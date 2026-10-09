#!/usr/bin/env bash
# Set up Deskflow input injection INTO Hyprland / Omarchy.
# Idempotent: safe to re-run. See README.md.
set -euo pipefail

BRIDGE_REPO="https://github.com/gfhdhytghd/hypr-kdeconnect-fix"
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREFIX="$HOME/.local"
PORTAL_CONF="$HOME/.config/xdg-desktop-portal/hyprland-portals.conf"
OVERRIDE_DIR="$HOME/.config/systemd/user/hypr-kdeconnect-portal.service.d"

say() { printf '\n==> %s\n' "$*"; }

command -v hyprctl >/dev/null || { echo "This targets Hyprland. hyprctl not found."; exit 1; }

# 1) Deskflow (the KVM client). Needs AUR? No: it's in Arch 'extra'.
if ! command -v deskflow-core >/dev/null 2>&1; then
  say "Installing deskflow (needs sudo)"
  sudo pacman -S --needed --noconfirm deskflow
fi

# 2) Build + install the RemoteDesktop portal bridge to ~/.local.
if [[ ! -x $PREFIX/bin/hypr-kdeconnect-portal ]]; then
  say "Building the RemoteDesktop portal bridge ($BRIDGE_REPO)"
  for dep in cmake git pkg-config; do
    command -v "$dep" >/dev/null || { echo "Missing build tool: $dep"; exit 1; }
  done
  src="$(mktemp -d)"
  git clone --depth 1 "$BRIDGE_REPO" "$src"
  cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DHKCF_DESKFLOW_EXECUTABLE=/usr/bin/deskflow-core
  cmake --build "$src/build" -j"$(nproc)"
  cmake --install "$src/build"
  rm -rf "$src"
else
  say "Bridge already installed at $PREFIX/bin/hypr-kdeconnect-portal"
fi

# 3) systemd override — the namespace fix (see README). This is the part that
#    makes authorization actually work.
say "Installing systemd override (namespace fix)"
mkdir -p "$OVERRIDE_DIR"
cp "$HERE/systemd/hypr-kdeconnect-portal.service.d/override.conf" "$OVERRIDE_DIR/override.conf"

# 4) Route only RemoteDesktop to the bridge, preserving existing providers.
say "Configuring portal routing -> $PORTAL_CONF"
mkdir -p "$(dirname "$PORTAL_CONF")"
if [[ ! -f $PORTAL_CONF ]]; then
  cp "$HERE/xdg-desktop-portal/hyprland-portals.conf" "$PORTAL_CONF"
elif ! grep -q 'RemoteDesktop=hypr-kdeconnect' "$PORTAL_CONF"; then
  cp "$PORTAL_CONF" "$PORTAL_CONF.bak.$(date +%s)"
  if grep -q '^\[preferred\]' "$PORTAL_CONF"; then
    sed -i '/^\[preferred\]/a org.freedesktop.impl.portal.RemoteDesktop=hypr-kdeconnect' "$PORTAL_CONF"
  else
    printf '\n[preferred]\norg.freedesktop.impl.portal.RemoteDesktop=hypr-kdeconnect\n' >>"$PORTAL_CONF"
  fi
fi

# 5) Reload.
say "Reloading portal + bridge"
systemctl --user daemon-reload
systemctl --user restart xdg-desktop-portal.service 2>/dev/null || true
systemctl --user restart hypr-kdeconnect-portal.service 2>/dev/null || true
sleep 1

# 6) Verify.
if busctl --user introspect org.freedesktop.portal.Desktop \
     /org/freedesktop/portal/desktop 2>/dev/null | grep -q RemoteDesktop; then
  say "RemoteDesktop portal is exposed ✔"
else
  echo "RemoteDesktop portal not visible yet — try logging out/in."
fi

cat <<'NEXT'

==> Done. Quick injection self-test (moves your cursor):
      hypr-kdeconnect-portal --self-test-motion 120 0

==> Next:
  - On the server (Mac/Windows with the keyboard, running Synergy/Deskflow as
    SERVER): add a screen named EXACTLY like this client's computer name, next
    to your screen; note the server's IP (or Tailscale IP).
  - Here: open `deskflow` as CLIENT, point it at that IP, match TLS on both
    ends (or disable on both; Tailscale already encrypts), Start, then move the
    server cursor toward this screen.
  - Watch it authorize:  journalctl --user -u hypr-kdeconnect-portal.service -f
NEXT
