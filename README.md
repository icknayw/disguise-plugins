# NRMW Disguise Plugins

Four independent Windows plugins for Disguise Designer. Install only the folders you need.

| Plugin | Purpose | Local port | Runtime |
| --- | --- | --- | --- |
| [Device Monitor](device-monitor/) | ICMP reachability and latency | 18743 | Windows PowerShell 5.1 |
| [Projector Monitor](projector-monitor/) | Panasonic power, shutter and status; up to 12 projectors | 18745 | Windows PowerShell 5.1 |
| [World Clock](world-clock/) | Up to 8 timezones, configurable sizes | 18753 | Windows PowerShell 5.1 |
| [Videohub Monitor](videohub-monitor/) | Blackmagic routing matrix, batch Take and port filters | 18751 | Node.js 22 or newer |

## Install

1. Download the repository using **Code > Download ZIP**, then extract it.
2. Copy the desired plugin folder into your project's `plugins` folder, or `d3 Projects/common/plugins`.
3. Run its `Start.cmd`, then open Designer's **Plugins** launcher. `Open-in-Designer.cmd` opens the local panel directly when Designer is running.
4. Open **Settings** and enter your own devices. No show configuration or credentials are included.

Designer can load each folder's Python startup hook on project launch. Helpers run as separate Windows processes. Use `Stop.cmd` to stop a helper; closing its panel does not stop it. Restarting the project or running Start starts it again.

Keep a backup of your configuration before updating. Stop the helper, replace code files, retain locally generated JSON settings, then start it again. Projector passwords are protected for the Windows user and machine that saved them; re-enter them after moving hosts.

## Deployment notes

Developed and exercised with Designer r32.4.18 on Windows. These are independent NRMW tools, not Disguise-certified products. Native window fitting uses Designer's internal Python GUI objects and can need adjustment for other versions. Test on an editor before production deployment.

Defaults bind locally. Projector Monitor and Videohub Monitor can be shared across a trusted control network; see their README files. They provide equipment controls without user authentication. Do not expose them to the internet. A shared helper must remain running for other machines to use it.

Compact, Standard and Large use matching baseline widths. Matrix windows grow with visible ports. Power, shutter and Take buttons operate real equipment.

## Version and tests

Initial repository release: **1.0.0**. See [CHANGELOG.md](CHANGELOG.md). Loopback Videohub tests are in `tests`; no hardware is contacted by these tests.

NRMW
