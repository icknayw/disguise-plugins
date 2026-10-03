# World Clock

Tokyo, London and New York by default, displaying hours and minutes. Settings lets you choose 1 to 8 IANA timezones and Compact, Standard or Large. Daylight-saving offsets are handled by the browser timezone database; the host computer's clock must be correct.

Requires Windows PowerShell 5.1; no Node.js installation is needed. Open http://127.0.0.1:18753/. Settings are stored in `clock-settings.json`. The window follows the chosen size and timezone count.

## Installation

Copy this folder into your Designer project `plugins` directory, or the shared `d3 Projects/common/plugins` directory. Run `Start.cmd`, then open it in the Plugins launcher. `Open-in-Designer.cmd` is an alternative. Use `Stop.cmd` before updating or moving the helper.
