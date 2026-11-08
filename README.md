# RDP on a GitHub runner, files on your E: drive

A Windows Server 2022 runner joins your tailnet for a few hours, you connect with
RDP, and everything you touch is stored on `E:\RDP` on your own PC. When the run
ends the VM disappears; your files do not.

Repo: `ILMaRkz-Y/RDP-Limy` · workflow: `.github/workflows/main.yml`

---

## Start a session

Actions -> **rdp + files on E:** -> *Run workflow*

| Input | Meaning |
|---|---|
| `duration_minutes` | how long the VM stays up, max 300 |
| `sync_every_minutes` | how often small files are copied back to E: |

It takes about 90 seconds to boot, install Tailscale, mount the share and restore
your files.

## Connect

The node is named `rdp-<run id>`. On any device in your tailnet:

```
tailscale status
100.107.21.28   rdp-42525833831   windows   active
```

or just read the top of the *7. session* step log, which prints a banner:

```
========== YOUR RDP ==========
  host  : 100.107.21.28
  user  : util
  pass  : your RDP_PASSWORD secret
  E: as : Z: after you log in
```

Open `mstsc`, paste the IP, log in as `util` with `RDP_PASSWORD`.

**One env var, every run.** The address changes with every run because the node
is ephemeral. Never bookmark it; read it from `tailscale status`.

---

## Where things live

| Folder | Where | How |
|---|---|---|
| `.minecraft` | `E:\RDP\files\minecraft` | junction |
| Modrinth `profiles` | `E:\RDP\files\modrinth\profiles` | junction |
| Modrinth `meta` | `E:\RDP\files\modrinth\meta` | junction |
| Modrinth `store` | `E:\RDP\files\modrinth\store` | junction |
| `horizon-launcher` | `E:\RDP\files\horizon-launcher` | junction |
| Modrinth `app.db` | `E:\RDP\profile\AppData\Roaming\ModrinthApp` | copied |
| Firefox profile | `E:\RDP\profile\AppData\Roaming\Mozilla` | copied |
| Limyrx config | `E:\RDP\profile\AppData\Roaming\Limyrx` | copied |
| Spotify login | `E:\RDP\profile\AppData\Roaming\Spotify` | copied |
| VS Code settings | `E:\RDP\profile\AppData\Roaming\Code\User` | copied |
| `Documents` `Downloads` `Music` | `E:\RDP\profile\...` | copied |
| `.ssh` `.gitconfig` | `E:\RDP\profile\...` | copied |

**Junction** means the runner does not copy anything: at logon it maps
`Z:` to `\\100.120.215.94\RDP\files` and points `%APPDATA%\.minecraft` at
`Z:\minecraft`. The game reads and writes your disk directly, so a 26 GB modpack
costs nothing at boot.

Your own PC uses the same folders through junctions too (created by
`adopt-local.ps1`), so there is exactly **one** copy of everything and both
machines see it.

## Why some things are copied, not junctioned

`app.db` is SQLite in WAL mode, which keeps a shared-memory segment (`-shm`) next
to the database. That does not work over SMB, so the database stays on the
runner's local disk and is copied to/from E: at boot and at the end.

`Desktop` (71.8 GB, 1,033,676 files) and `Pictures` (46.2 GB) are **not** in the
sync list. Copying 122 GB — or even just rescanning a million files — every five
minutes is slower than the work it saves. If you want them in the session, move
them to `E:` and junction them the same way as `.minecraft`:

```
powershell -File E:\rdp-kit\adopt-local.ps1 -IncludeDesktop
```

## The runner account is called `util` on purpose

Modrinth's `app.db` and most launcher configs store absolute paths like
`C:\Users\util\AppData\Roaming\...`. If the runner's account were called `RDP`,
every stored path would be wrong and your instances would show as missing. Same
name, same path, same data.

---

## Browser logins: Firefox works, Chrome cannot

Chrome and Edge encrypt their cookie database with a key in
`User Data\Local State`, sealed with **DPAPI**, bound to the Windows user's SID.
The runner builds a new account every run, so the old key cannot be unsealed.
Copying `User Data` gets you bookmarks, extensions and settings — the sites still
log you out.

Firefox keeps logins in `logins.json` + `key4.db` inside the profile, with no
OS-bound key. Copy the profile and the sessions come with it.

Chrome with Sync signed in: passwords and bookmarks survive, session cookies do not.

---

## Apps

`Modrinth App` installs itself from its GitHub release
(`Modrinth.App_x.y.z_x64-setup.exe`, run with `/S`).

Anything else: drop the installer `.exe` in `E:\RDP\installers` and it runs
before the session starts. NSIS installers take `/S`, Inno Setup takes
`/VERYSILENT`.

Cracked launchers: put the installer in `E:\RDP\installers` yourself. Their data
lives in `AppData\Roaming\<Name>` — add that folder to `HEAVY` and the note about
junctions above, and their instances survive.

---

## Things that will bite you

**Your PC has to be awake and on Tailscale.** Otherwise step 4 retries for 2.5
minutes and fails with `cannot reach \\100.120.215.94\RDP`.

**Close the launcher and the browser before the session ends.** `app.db`,
`cookies.sqlite` and `places.sqlite` are locked while their app runs, so the
final copy skips them.

**Deletions do not propagate.** `robocopy /E` adds and overwrites, never deletes
on E:. Swap `/E` for `/MIR` in `sync.ps1` if you want mirroring — but then a bad
restore can delete real files.

**Games on `Z:` load slower.** Every asset read is a network round trip. A few
extra seconds at start-up is the price of not copying 30 GB twice per run.

**The Tailscale auth key must be created as Ephemeral** in the admin console.
`tailscale up` has no `--ephemeral` flag; ephemerality is a property of the key.

**Password policy.** The local policy on the runner rejects short or simple
passwords, so step 2 relaxes `PasswordComplexity` / `MinimumPasswordLength`
before creating the account. Any `RDP_PASSWORD` works.

**A stuck run can poison the concurrency group.** A run that sits in `queued`
with `total_count: 0` jobs and refuses to cancel holds the group, and every later
run queues behind it forever. The fix is to change `concurrency.group` in the
workflow (it is `rdp-session` now) and push.

**If the tailnet IP of your PC changes**, edit `PC:` in the workflow and in the
`net use` line of step 7.
