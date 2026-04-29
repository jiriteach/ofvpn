# 🔂 - OFVPN

OFVPN is a small native macOS menu bar GUI application for [`openfortivpn`](https://github.com/adrienverge/openfortivpn). It wraps the command-line VPN workflow into a simple menu bar application with status, external/internal IP display, connect/disconnect controls, and log information.

The application is designed for users who currently connect with:

```sh
sudo openfortivpn -c "$HOME/Documents/.fortivpn-config"
```

## Features

- Menu bar-only macOS application.
- Connects with `openfortivpn` using a remembered configuration file.
- Shows connection state in the menu bar.
- Shows external IP and internal IPv4 addresses.
- Provides Connect, Disconnect, Check Logs, and Exit actions.
- Prompts before exiting while connected and can disconnect before quitting.
- Disconnect does not require a second password prompt after a successful connect.

## Screenshots

### Connected

![OFVPN connected state](Screenshots/Screenshot%202026-04-28%20at%2022.29.10.png)

### Disconnected

![OFVPN disconnected state](Screenshots/Screenshot%202026-04-28%20at%2022.29.47.png)

### About

![OFVPN about page](Screenshots/Screenshot%202026-04-28%20at%2022.29.54.png)

## Requirements

- macOS 13 or newer.
- Apple Command Line Tools or Xcode.
- Homebrew.
- `openfortivpn`.
- A valid `openfortivpn` configuration file, for example:

```text
$HOME/Documents/.fortivpn-config
```

## Install openfortivpn

Install Homebrew if needed:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install `openfortivpn`:

```sh
brew install openfortivpn
```

Check it is available:

```sh
openfortivpn --version
```

## Configure openfortivpn

Create or copy your existing configuration file. A typical location is:

```sh
mkdir -p "$HOME/Documents"
touch "$HOME/Documents/.fortivpn-config"
chmod 600 "$HOME/Documents/.fortivpn-config"
```

Example configuration file:

```ini
host = vpn.server.com
port = 443
username = your.username
password = your.password
trusted-cert = <certificate-digest-if-required>
```

## Build OFVPN

Clone the repository, then build the application:

```sh
chmod +x build-app.sh package-dmg.sh
./build-app.sh
```

The application bundle is created at:

```text
.build/OFVPN.app
```

Run it locally:

```sh
open ".build/OFVPN.app"
```

## First Launch

On first launch, OFVPN asks you to select your `openfortivpn` config file. The selected path is remembered for future launches.

When connecting, macOS shows an administrator authorization prompt because `openfortivpn` needs elevated privileges to configure the tunnel.

## Install Locally

After building, copy the application to Applications:

```sh
cp -R ".build/OFVPN.app" /Applications/
open "/Applications/OFVPN.app"
```

If you rebuild frequently, quit the running application first:

```sh
pkill -x FortiVPNMenuBar 2>/dev/null || true
```

## Package a DMG for Releases

Build the application and create a compressed DMG:

```sh
./build-app.sh
./package-dmg.sh
```

The DMG is created at:

```text
.build/OFVPN-<version>.dmg
```

For example:

```text
.build/OFVPN-1.26.dmg
```

## Release Checklist

1. Update the version in `build-app.sh`.
2. Make sure `Other/applicationIcon.png` exists. The build script converts it into `OFVPN.icns` and includes it in the app bundle.
3. Build the application:

```sh
./build-app.sh
```

4. Create the DMG:

```sh
./package-dmg.sh
```

5. Test the DMG locally by opening it and dragging `OFVPN.app` to Applications.

## Logs

OFVPN writes connection logs to the current user's temporary directory:

```text
$TMPDIR/fortivpn-menubar/openfortivpn-current.log
```

Use `Check Logs` from the menu bar to open the current log.

## Notes

- OFVPN is a GUI wrapper around `openfortivpn`; it does not replace `openfortivpn`.
- Disconnect is handled by a small root-side watcher started during Connect, so disconnecting does not require a second password prompt.
- The built app is unsigned. On some Macs, Gatekeeper may require you to right-click and choose Open the first time, or to sign/notarize the app for organization-wide distribution.

## Attribution

Application icon created by Secret Studio - Flaticon - https://www.flaticon.com/free-icon/vpn_5175160?term=vpn&page=1&position=4&origin=search&related_id=5175160
