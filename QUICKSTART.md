# Cisco Migration — Quick Start

## Setup (once, on the server)
Copy these files into your migration folder on the server:
- `Install-Cisco.ps1`
- `Run-Install.cmd`
- `Run-DryRun.cmd`
- `Run-Preflight.cmd`

They travel with the folder every time you copy it to a client.

## Safety ladder (read-only → real)
1. `Run-Preflight.cmd` — does it find the files? (read-only)
2. `Run-DryRun.cmd` — what exactly would it do? (read-only)
3. `Run-Install.cmd` — actually do it.

## Field steps (each client)
1. Copy migration folder to client (as usual)
2. Open the copied folder
3. Double-click **`Run-Preflight.cmd`** → click Yes (admin) → must show **GREEN**
4. Double-click **`Run-Install.cmd`** → click Yes (admin) → watch it run
5. Browser opens → **Roaming Info → RC Name** must show this PC's name ✓

## If something goes wrong
Log file at: `C:\ProgramData\CiscoMigration\logs\`

## Exit codes
| Code | Meaning |
|------|---------|
| `0` | All good |
| `1` | Stopped — see RED lines in log |
| `2` | Installed but verify warning — check scorecard |
