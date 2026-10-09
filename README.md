# Deskflow (Synergy) keyboard/mouse sharing INTO Hyprland / Omarchy

Use another computer's keyboard and mouse (a **macOS or Windows machine running
Synergy v1 / Deskflow / Barrier as the *server***) to control a **Hyprland**
(e.g. [Omarchy](https://omarchy.org/)) machine as the *client* — the cursor
crosses screen edges and the keyboard follows, like a software KVM. Works over
LAN or [Tailscale](https://tailscale.com/) (so the two machines can be on
different networks).

This repo is the **missing glue** to make the *receiving* (injection) side work
on Hyprland. The clients themselves ([Deskflow](https://github.com/deskflow/deskflow),
Input Leap, Synergy) already exist.

## The problem

On Wayland a client can't just inject input into other apps. Deskflow/Synergy
ask the desktop for the **`org.freedesktop.portal.RemoteDesktop`** portal and
inject through it. GNOME and KDE implement that portal; **Hyprland does not**
(as of `xdg-desktop-portal-hyprland` 1.4.x). So the client connects fine but the
cursor never moves and the keyboard does nothing. You'll see:

```
ERROR: failed to initialize remote desktop session:
  No such interface "org.freedesktop.portal.RemoteDesktop"
```

## The fix (two parts)

1. **A RemoteDesktop portal backend for Hyprland.** The excellent
   [`gfhdhytghd/hypr-kdeconnect-fix`](https://github.com/gfhdhytghd/hypr-kdeconnect-fix)
   implements exactly this (injecting through `wlr-virtual-pointer` +
   `virtual-keyboard`, with libei `ConnectToEIS` support). It explicitly
   supports Deskflow.

2. **A one-line systemd override — the part that is easy to miss.** The bridge
   authorizes Deskflow by reading `/proc/<pid>/exe` of the caller. But its
   default systemd hardening (`PrivateTmp` / `ProtectSystem` / `ProtectHome`)
   puts the **user** service in a private **user namespace**, and from inside
   that namespace it **cannot read** another process's `/proc/<pid>/exe`
   (cross-user-namespace permission denial). Result: it silently **refuses
   every session**:

   ```
   refusing RemoteDesktop session for app id ""
   ```

   The override in [`systemd/.../override.conf`](systemd/hypr-kdeconnect-portal.service.d/override.conf)
   disables that isolation so the bridge can verify the caller. Without it, the
   bridge builds, runs, and still refuses everything.

> **Security note:** the override relaxes the bridge service's sandbox. The
> bridge grants local input injection, so only run this on a machine you trust
> as a single user. The bridge still restricts *which* caller it authorizes
> (`/usr/bin/deskflow-core`, KDE Connect).

## Quick start

```sh
git clone https://github.com/<you>/omarchy-deskflow-kvm
cd omarchy-deskflow-kvm
./setup.sh
```

`setup.sh` is idempotent. It:

- installs `deskflow` (pacman),
- builds + installs the bridge to `~/.local` (from upstream),
- installs the systemd **override** (the namespace fix),
- routes only `RemoteDesktop` to the bridge in `~/.config/xdg-desktop-portal/hyprland-portals.conf`,
- reloads the portal.

Then verify injection works even before touching the other machine:

```sh
hypr-kdeconnect-portal --self-test-motion 120 0   # your cursor should jump +120px
```

## Configure the two machines

**On the server (the Mac/Windows with the keyboard), running Synergy v1 / Deskflow:**

- Set it as **Server**.
- In the screen layout, add a screen next to yours and **name it exactly like the
  Hyprland client's computer name** (e.g. `omarchy`). A name mismatch = the
  cursor won't cross.
- Note its IP (LAN, or its **Tailscale** IP to work across networks).

**On the Hyprland client:**

- Open `deskflow`, choose **Client**.
- Server address = the server's IP / Tailscale IP.
- Client screen name must match the layout entry (defaults to the hostname).
- **TLS:** match both ends. Over Tailscale the transport is already encrypted, so
  disabling TLS on both is fine and avoids fingerprint hassles.
- Start, then move the server's cursor toward the client's screen.

## Verify / troubleshoot

Watch the bridge decide:

```sh
journalctl --user -u hypr-kdeconnect-portal.service -f
```

- `allowing RemoteDesktop session … /usr/bin/deskflow-core` → working.
- `refusing … app id ""` → the override isn't applied (re-run `setup.sh`, then
  `systemctl --user daemon-reload && systemctl --user restart hypr-kdeconnect-portal`).
- `Failed to connect … check your TLS and firewall` → TLS mismatch (match both
  ends) or wrong IP / server not listening on `:24800`.
- Connects but cursor won't cross → the server's layout screen name doesn't match
  the client's computer name.

## Known issues

**macOS "ghost cursor" (server side).** When the server is a Mac and you cross
to the Hyprland client, the Mac often doesn't fully hide its own pointer — it
parks it mid-screen and leaves it visible. This is a long-standing
Synergy/Deskflow macOS limitation, unrelated to this bridge (the client side is
fine). Mitigations, all on the Mac:

- Grant the server app **Accessibility**, **Input Monitoring** and **Screen
  Recording** in *System Settings → Privacy & Security* — missing permissions
  can break cursor hiding.
- Run **Deskflow** (latest) on the Mac instead of an old Synergy 1.x — same
  project, better-maintained cursor handling, and both ends match.
- As a reliable fallback, use a macOS cursor hider such as **Cursorcerer** (hide
  the pointer after a few seconds idle or via hotkey); while you're on the
  client the Mac pointer is idle, so it hides itself.

## Status / upstreaming

Native RemoteDesktop support is being added to `xdg-desktop-portal-hyprland`
([PR #402](https://github.com/hyprwm/xdg-desktop-portal-hyprland/pull/402),
[PR #428](https://github.com/hyprwm/xdg-desktop-portal-hyprland/pull/428)). Once
that lands, the bridge in part (1) may become unnecessary — but you'll likely
still want to be aware of the namespace/authorization gotcha.

## Credits

- [Deskflow](https://github.com/deskflow/deskflow) — the KVM client/server (the
  continuation of Synergy's open-source core).
- [gfhdhytghd/hypr-kdeconnect-fix](https://github.com/gfhdhytghd/hypr-kdeconnect-fix)
  — the RemoteDesktop portal bridge that does the actual injection. This repo
  only documents how to wire it up on Hyprland/Omarchy and the systemd override
  needed to make authorization work.

## License

MIT — see [LICENSE](LICENSE).
