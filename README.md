# Cisco Secure Client Migration Automation

Automates silent deployment of **Cisco Secure Client** (formerly AnyConnect) with
Umbrella roaming, ISE Posture, ISE Compliance, and DART modules on Windows endpoints.

Designed for sysadmins who copy a migration folder to each client machine and want
one-click install + verification instead of clicking through wizards every time.

---

## What it does

Three phases run in sequence:

| Phase | What happens |
|-------|-------------|
| **LOOK** | Validation-only preflight. Finds every required file, checks admin rights, and prints GREEN or RED. It skips installation actions but writes a local log. |
| **INSTALL** | Imports the root CA cert, installs all 5 MSI modules in the correct dependency order, drops the 2 config files. Stops on first failure. |
| **CHECK** | Verifies cert, products, service, config files, and Umbrella folders. Prints a PASS/FAIL scorecard. Opens the Umbrella Policy Checker so you can confirm cloud registration. |

Already-installed components are skipped on subsequent runs.

---

## Files

| File | Purpose |
|------|---------|
| `Install-Cisco.ps1` | The engine. All logic lives here. |
| `Run-Install.cmd` | Double-click → full run (LOOK + INSTALL + CHECK). Self-elevates to admin. |
| `Run-Preflight.cmd` | Double-click → LOOK only. It installs nothing but writes a local log. |
| `Run-DryRun.cmd` | Double-click → preview every action without executing anything. No admin needed. |
| `README.md` | This file. |
| `QUICKSTART.md` | One-page field reference. |
| `.gitignore` | Blocks accidental commit of certs, configs, MSIs, logs. |

---

## Requirements

- Windows 10 / 11 endpoint
- PowerShell 5.1+
- Administrator rights (`.cmd` launchers prompt automatically)
- Migration folder already copied to the local machine — this script does **not**
  pull from a server; it operates on what is already present locally

---

## Usage

### Safety ladder — run in this order

```
Run-Preflight.cmd   →   does it find all the files?   (no install actions)
Run-DryRun.cmd      →   what exactly would it do?      (preview only)
Run-Install.cmd     →   actually do it                 (admin, real changes)
```

The first two skip certificate import, MSI installation, and configuration-file
copies. They still create a local log under `C:\ProgramData\CiscoMigration\logs`.
Test the workflow on a representative non-production endpoint and review the
output before using it in production.

### Field steps (each client)

1. Copy the migration folder to the client machine (as you normally do).
2. Open the copied folder.
3. Double-click **`Run-Preflight.cmd`** → click *Yes* (admin) → confirm **GREEN**.
4. Double-click **`Run-Install.cmd`** → click *Yes* (admin) → watch it run.
5. Browser opens → **Roaming Info → RC Name** must show this PC's hostname.

---

## File discovery

Files are found **by name pattern** recursively under the migration folder.
Exact folder names, subfolder layout, and version numbers do not matter.

| Required piece | Matched by |
|----------------|-----------|
| Root CA certificate | `*.cer` or `*.crt` |
| Core VPN (installed first) | `*core-vpn*predeploy*.msi` |
| Umbrella | `*umbrella*predeploy*.msi` |
| ISE Posture | `*iseposture*predeploy*.msi` |
| ISE Compliance | `*isecompliance*predeploy*.msi` |
| DART (installed last) | `*dart*predeploy*.msi` |
| Umbrella config | `OrgInfo.json` |
| ISE config | `ISEPostureCFG.xml` |

If any piece is **missing** or there are **two matches**, LOOK reports RED and
nothing is installed. The script never guesses.

---

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success (GREEN preflight, or full run all-PASS) |
| `1` | Stopped before or during install — see RED lines in log |
| `2` | Installed, but a verify check failed — check scorecard and log |

---

## Logs

Each run writes to:

```
C:\ProgramData\CiscoMigration\logs\install_<timestamp>.log
```

Each MSI also writes `msi_<module>_<timestamp>.log` in the same folder.

---

## Testing before using a client endpoint

- **`Run-Preflight.cmd`** — confirms file discovery without running install actions. It still writes a local log.
- **`Run-DryRun.cmd`** — prints every msiexec command and file copy it *would* run, executes none of it.
- **VM snapshot** — run `Run-Install.cmd` on a Windows VM, snapshot first, revert after. Real end-to-end test with an undo.

---

## Security notes

> **This section applies to the migration folder, not to these scripts.**
> These scripts contain no credentials, no org identifiers, and no company-specific data.

- `OrgInfo.json` — contains your org's Umbrella registration token. **Do not commit it.
  Do not put the migration folder on a public or open share.**
- The root CA certificate (`*.cer`/`*.crt`) — your org's SSL-inspection CA. Keep access-controlled.
- `ISEPostureCFG.xml` — may reference internal server hostnames. Treat as internal.
- The `.gitignore` in this repo blocks all of the above file types from being accidentally committed.

---

## One-time setup

Copy `Install-Cisco.ps1`, `Run-Install.cmd`, `Run-Preflight.cmd`, `Run-DryRun.cmd`,
and `QUICKSTART.md` into your migration folder on the source server alongside the
Cisco MSIs and config files. They travel with the folder to every client automatically.

---

## License

See [LICENSE](LICENSE).
