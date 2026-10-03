# Projector Monitor

Panasonic network status with power and shutter control. Add up to 12 projectors, choose one/two/four columns, and choose Compact, Standard or Large. Device support depends on the Panasonic model and enabled network-command interface.

Requires Windows PowerShell 5.1. Open http://localhost:18745/. Enter name, IPv4 address, command port (default 1024), username and password in Settings. Start with one blank projector. Configuration is stored in `fleet.json`; passwords use Windows DPAPI CurrentUser protection.

## Shared hosting

Copy `network.example.json` to `network.json`. Replace the documentation addresses with the host's real `bindAddress` and the permitted editor/understudy `allowedClients`. Restart the helper. Windows may require an HTTP URL reservation and an inbound firewall rule scoped to those clients. These are not changed automatically.

On client machines, install a folder containing only a `d3plugin.json` pointing its `url` at `http://HOST-IP:18745/`. Do not run a second helper for the same shared setup. Use the configured IP in the browser URL. Saved projector credentials stay on the host.

## Installation

Copy this folder into your Designer project `plugins` directory, or the shared `d3 Projects/common/plugins` directory. Run `Start.cmd`, then open it in the Plugins launcher. `Open-in-Designer.cmd` is an alternative. Use `Stop.cmd` before updating or moving the helper.
