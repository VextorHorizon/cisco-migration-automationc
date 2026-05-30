# Cisco Secure Client + Umbrella + ISE — Automated Installer

Automates the 8-step manual migration (cert import + Cisco Secure Client modules +
Umbrella/ISE config) so you stop clicking through wizards on every client machine.

It does **not** copy the migration folder from the server — you do that the way you
already do. The script runs **locally on the client**, against the folder you copied.

---

## Files

| File | What it is |
|------|------------|
| `Install-Cisco.ps1` | The engine. Does everything. |
| `Run-Install.cmd` | Double-click → full run (LOOK → INSTALL → CHECK). Self-elevates to admin. |
| `Run-DryRun.cmd` | Double-click → preview. Prints every action it WOULD take, executes nothing. Read-only, no admin. |
| `Run-Preflight.cmd` | Double-click → LOOK only (read-only, installs nothing). Your safe test. |
| `README.md` | This file. |

**Safety ladder:** `Run-Preflight` (does it find the files?) → `Run-DryRun` (what exactly would it do?) → `Run-Install` (do it). The first two are read-only and safe on a real client.

---

## What it does (3 phases)

1. **LOOK (Preflight)** — read-only. Searches the migration folder, confirms all 6
   required pieces are present, checks admin rights. Prints **GREEN** (safe) or
   **RED** (stop). Changes nothing.
2. **INSTALL** — only if LOOK was GREEN. Imports the cert, installs the 5 MSIs in the
   correct order, drops the 2 config files. Stops on the first failure.
3. **CHECK** — verifies cert / products / service / config / Umbrella folders, prints a
   **PASS/FAIL scorecard**, opens the Umbrella **Policy Checker** and prints this PC's
   hostname so you can confirm the cloud registered the device.

It finds files **by name pattern**, recursively, anywhere under the folder — so the
exact folder name, version number, and subfolder layout do **not** matter:

| Piece | Found by |
|-------|----------|
| Certificate | `*.cer` / `*.crt` |
| Core VPN (installed 1st) | `*core-vpn*predeploy*.msi` |
| Umbrella | `*umbrella*predeploy*.msi` |
| ISE Posture | `*iseposture*predeploy*.msi` |
| ISE Compliance | `*isecompliance*predeploy*.msi` |
| DART (installed last) | `*dart*predeploy*.msi` |
| Umbrella config | `OrgInfo.json` |
| ISE config | `ISEPostureCFG.xml` |

If any piece is **missing** or there are **two matches**, LOOK reports RED and nothing
is installed. The script never guesses.

---

## One-time setup (on the server)

Copy `Install-Cisco.ps1`, `Run-Install.cmd`, and `Run-Preflight.cmd` into your
migration folder on the server (e.g. the `Migration` folder that contains
`Umbrella-5.1.x`). After that, every time you copy the folder to a client, the
scripts come with it automatically.

The scripts can sit at the top of the folder or anywhere inside it — they search
downward from their own location.

---

## Field workflow (on each client)

1. Copy the migration folder to the client (`C:\Migration\...`), the way you do now.
2. Open the copied folder.
3. **First time / new build type:** double-click **`Run-Preflight.cmd`**. Click *Yes*
   on the admin prompt. Confirm it prints **GREEN**. (Optional but recommended.)
4. Double-click **`Run-Install.cmd`**. Click *Yes* on the admin prompt.
5. Watch: LOOK → INSTALL → CHECK. Read the scorecard.
6. A browser tab opens to the **Policy Checker**. In **Roaming Info → RC Name**,
   confirm it shows the hostname the script printed. That is the real proof.

---

## How to test it WITHOUT risking a client

- **Preflight anywhere:** `Run-Preflight.cmd` is read-only. Run it on any machine that
  has a copy of the folder to prove the file-finding works. Zero risk.
- **Full run on a throwaway VM:** take a Windows VM, snapshot it, run `Run-Install.cmd`,
  check the scorecard, then revert the snapshot. Real end-to-end test with an undo.
- Only after the VM passes, take it to real clients — and run Preflight first each time.

---

## Exit codes (for RMM / scripting)

| Code | Meaning |
|------|---------|
| `0` | All good (GREEN preflight, or full run all-PASS). |
| `1` | Stopped before/at install (RED preflight, not admin, or an MSI failed). |
| `2` | Installed, but a verify check failed — look at the scorecard/log. |

---

## Logs

Every run writes to:

```
C:\ProgramData\CiscoMigration\logs\install_<timestamp>.log
```

Each MSI also writes its own `msi_<module>_<timestamp>.log` in the same folder. If
something fails, read the log instead of guessing.

---

## Safe to re-run

The script is idempotent: an already-imported cert and already-installed modules are
**skipped**. Running it twice does not double-install or break anything.

---

## Notes / caveats

- **Run as admin.** The `.cmd` launchers prompt for it automatically (UAC).
- **`Umbrella data + SWG` check may say "NOT YET".** Those folders appear after the
  Umbrella agent starts reading `OrgInfo.json`; sometimes that needs a reboot. It's a
  warning, not a hard failure — reboot and re-run CHECK if needed.
- **ISE Posture "No policy server detected" is normal off-network.** ISE posture only
  fully verifies when the machine is on the corporate network with the ISE server.

### Security
- The cert is the **Umbrella SSL-inspection root CA**. Installing it lets Umbrella
  decrypt TLS on these machines. Expected for Umbrella — but keep the package
  access-controlled.
- `OrgInfo.json` contains your **org registration token**. Do not put this package on
  a public or wide-open share.
