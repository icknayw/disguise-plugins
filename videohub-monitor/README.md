# Videohub Monitor

Blackmagic Videohub TCP protocol monitor and routing control. Select visible inputs and outputs in Settings. Choose inputs on the left or on top. The window fits the visible matrix.

Requires Windows PowerShell and **Node.js 22 or newer**. Install Node from https://nodejs.org/ or place an official Windows `node.exe` in `runtime/node.exe`. An existing Companion Node 22 runtime can also be used. No npm packages are required and no runtime binaries are included.

Open http://127.0.0.1:18751/. Enter the matrix IPv4 address; the protocol uses TCP port 9990. Saved IP, filters, size and orientation are stored in `settings.json`.

## Routing

Select multiple crosspoints and press **Take (N)**. Only one pending input is allowed per output. Clicking a selected crosspoint again removes it; choosing another input for that output replaces it. Cancel clears all pending selections. Selecting the currently active crosspoint clears that output's pending change.

Before transmission, all selected outputs are checked against fresh routing and lock status. One command contains the batch. Success requires ACK plus confirmation of every requested route. Hardware switching is not guaranteed to be atomic or frame-synchronous. On timeout, rejection or partial confirmation, inspect actual routing before retrying. The helper never automatically retries, rolls back or unlocks outputs. Audit events are saved locally in `routing-audit.ndjson`.

## Shared hosting

In `plugin-config.json`, set `bind` to the host's control-network IP (or `0.0.0.0`), and add its IP/hostnames to `allowedHosts`. The port defaults to 18751. Restart the helper and allow that TCP port through the host firewall only from your trusted control network.

Point each machine's `d3plugin.json` URL at `http://HOST-IP:18751/`. Client machines need only this manifest, not a second Node service. Host the backend on the machine you intend to keep running. Native window fitting targets the requesting Designer machine's API at port 80; browser-only clients do not need that API.

Protocol reference: https://documents.blackmagicdesign.com/DeveloperManuals/VideohubEthernetProtocol.pdf

## Installation

Copy this folder into your Designer project `plugins` directory, or the shared `d3 Projects/common/plugins` directory. Run `Start.cmd`, then open it in the Plugins launcher. `Open-in-Designer.cmd` is an alternative. Use `Stop.cmd` before updating or moving the helper.
