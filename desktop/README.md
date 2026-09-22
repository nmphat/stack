# Desktop (XFCE over RDP)

A graphical session on the Oracle box itself, so it can be used as an ordinary
workstation: browser with persistent logins, VS Code, an office suite, a visible
mouse pointer.

This is the only service in the stack that is **not** a container. The desktop
has to see `~/workspace`, `/var/run/docker.sock`, the hermes CLI and the
services bound to `127.0.0.1`. A container sees none of those, so it would be a
second machine sitting next to the one we actually want to use.

The Oracle image is Ubuntu Server: headless, no X server, no GUI applications.
Everything below is installed onto the host.

## Packages

| Package | Version | Why |
|---|---|---|
| `xfce4`, `xfce4-goodies` | 4.18 | Desktop environment. Light enough for 2 OCPU |
| `dbus-x11` | 1.14.10 | XFCE session bus |
| `xrdp` | 0.9.24 | RDP server |
| `xorgxrdp` | 1:0.9.19 | Creates its own X session, so no dummy driver or Xvfb is needed |
| `firefox` | 156.x | From `packages.mozilla.org`, a real .deb. The Ubuntu package is a snap transitional |
| `code` | 1.138.x | From `packages.microsoft.com`, arm64 is in the same suite |

All of these have arm64 builds. Google Chrome also has an official arm64 Linux
build with Widevine as of 2026-07-30, if Firefox is ever not enough:

```bash
curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_arm64.deb \
  -o /tmp/chrome.deb && sudo apt install -y /tmp/chrome.deb
```

## Ports

| Port | Bind | Description |
|---|---|---|
| 3389 | `127.0.0.1` | RDP, reached only through the Cloudflare tunnel |

## Configuration

Four files, all outside this repository:

**`/etc/xrdp/xrdp.ini`**

```ini
port=tcp://.:3389
```

`tcp://.` means `127.0.0.1`. A bare `port=3389` listens on every interface.
The syntax is documented in the commented block just above the setting.

**`~/.xsession`** — xrdp runs the session through `Xsession`, which reads this:

```sh
#!/bin/sh
exec startxfce4
```

**`/etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla`** — without it
every login pops an authentication dialog, because an RDP session is not a local
seat:

```ini
[Allow colord for remote sessions]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
```

**`lightdm`** — disabled. A headless box never uses a local display manager, and
xrdp starts its own session.

## Tunnel

```bash
sudo tunnel add oc-rdp 3389 tcp
```

RDP is not HTTP, so the ingress rule needs the `tcp://` scheme. The third
argument of `tunnel add` exists for this; without it the rule defaults to
`http://` and the connection fails during the RDP handshake.

Protect `oc-rdp.3p.id.vn` with a Cloudflare Access policy. It is the only gate
in front of a desktop that has full control of the host.

## Connecting

The client needs `cloudflared`, because Access has to authenticate the session
before any RDP traffic flows.

```powershell
winget install --id Cloudflare.cloudflared
cloudflared access rdp --hostname oc-rdp.3p.id.vn --url localhost:3389
```

macOS and Linux use `brew install cloudflared` or the distribution package, then
the same command. Leave that window running; it holds the tunnel open.

Then point any RDP client at `localhost:3389`:

| Field | Value |
|---|---|
| Computer | `localhost:3389` |
| Session | `Xorg` |
| Username | `ubuntu` |
| Password | the account password, not the SSH key |

`ubuntu` normally has no password on an Oracle image. Set one with
`sudo passwd ubuntu` before the first connection.

Reconnecting returns to the same session with the same windows still open.

## From a phone

`cloudflared access rdp` cannot run on Android or iOS, so the desktop client
route does not work there. Two alternatives:

**Cloudflare WARP.** Install the Cloudflare One app, enroll the phone in the
Zero Trust organization, add a private network route for `10.0.0.229/32` to the
tunnel, then connect Microsoft Remote Desktop to `10.0.0.229:3389`. This reaches
the same session and needs no new service on the host, but xrdp has to listen on
the private address as well:

```ini
port=tcp://.:3389,tcp://10.0.0.229:3389
```

**noVNC.** Attach a VNC server to the session and serve it over HTTP, which any
phone browser can open through the existing tunnel. This adds a service and a
second credential, and sharing one session between xrdp and VNC needs the
`[vnc-any]` module in `xrdp.ini` rather than `xorgxrdp`.

Cloudflare's browser-rendered RDP is not an option here: its documentation
requires a Windows RDP server, and this is xrdp on Linux.

## Resource notes

An idle XFCE session is around 450 MB. Firefox with a few tabs adds 1.5-2.5 GB,
VS Code around 700 MB. Firecrawl was removed from the stack to make room for
this; see the commit that dropped it.

Two OCPU is the real ceiling, not memory. Typing, VS Code and a handful of tabs
are comfortable. Video playback and heavy web applications are not, and no
amount of configuration changes that.

## Rebuilding

```bash
sudo apt-get install -y xfce4 xfce4-goodies dbus-x11 xrdp xorgxrdp
sudo systemctl disable --now lightdm
```

Then recreate the four configuration files above, add the Mozilla and Microsoft
apt repositories, install `firefox` and `code`, and re-add the tunnel rule.

## Verifying

```bash
systemctl is-active xrdp xrdp-sesman     # active active
ss -tlnp | grep 3389                     # 127.0.0.1:3389
sudo tail -5 /var/log/xrdp.log           # "listening to port 3389 on 127.0.0.1"
```
