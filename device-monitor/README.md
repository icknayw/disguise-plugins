# Device Monitor

Checks IPv4 devices using ICMP every 10 seconds, with concurrent 1.5-second timeouts. Shows reachability, latency and the last-check time. Online means a ping reply, not confirmation that the device's application is healthy.

Requires Windows PowerShell 5.1. Open http://localhost:18743/. Add/remove devices and select size and columns in Settings. Saved files: `devices.json` and `view.json`. A fresh installation starts with no devices.

## Installation

Copy this folder into your Designer project `plugins` directory, or the shared `d3 Projects/common/plugins` directory. Run `Start.cmd`, then open it in the Plugins launcher. `Open-in-Designer.cmd` is an alternative. Use `Stop.cmd` before updating or moving the helper.
