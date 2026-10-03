# Projector Monitor

Panasonic and Epson network status with power and shutter control. Add up to 12 projectors, mixing brands freely, choose one/two/four columns, and choose Compact, Standard or Large. Device support depends on the model and enabled network-control interface.

Requires Windows PowerShell 5.1. Open http://localhost:18745/. Enter brand, name, IPv4 address, port, username and password in Settings. Start with one blank projector. Configuration is stored in `fleet.json`; passwords use Windows DPAPI CurrentUser protection.

| Brand | Protocol | Default port | Default username |
| --- | --- | --- | --- |
| Panasonic | NTCONTROL over TCP | 1024 | `dispadmin` |
| Epson | ESC/VP21 over the projector's HTTP control API (`/api/v01/control/escvp21`), Digest authentication | 80 | `EPSONWEB` |

For Epson, enable web control on the projector. Use its Web Control password. Leave the password blank if none is set. Choose a Standby Mode that keeps network communication on, or the projector cannot be powered on remotely. Epson projectors answer most queries only when on. In standby the card shows power and faults, and the other readings are hidden until the projector is on.

Readings show only values the projector reports. Panasonic reports model, temperatures, projector hours and firmware. Epson reports signal and fault. Both report input, freeze, serial and light hours where supported.

## Shared hosting

Copy `network.example.json` to `network.json`. Replace the documentation addresses with the host's real `bindAddress` and the permitted editor/understudy `allowedClients`. Restart the helper. Windows may require an HTTP URL reservation and an inbound firewall rule scoped to those clients. These are not changed automatically.

On client machines, install a folder containing only a `d3plugin.json` pointing its `url` at `http://HOST-IP:18745/`. Do not run a second helper for the same shared setup. Use the configured IP in the browser URL. Saved projector credentials stay on the host.

## Installation

Copy this folder into your Designer project `plugins` directory, or the shared `d3 Projects/common/plugins` directory. Run `Start.cmd`, then open it in the Plugins launcher. `Open-in-Designer.cmd` is an alternative. Use `Stop.cmd` before updating or moving the helper. Existing `fleet.json` files from 1.0.0 load unchanged as Panasonic projectors.
