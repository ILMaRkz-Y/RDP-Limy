# RDP on a GitHub runner, files on your E: drive

Nothing gets installed on your PC. Four steps, once.

---

## 1. Share E:\RDP  (as admin, ~5 seconds)

Right-click `E:\rdp-kit\setup-my-pc.ps1` -> **Run with PowerShell**

It prints:

```
share path   : \\100.120.215.94\RDP
SMB_USER     : rdpsync
SMB_PASSWORD : <random, generated for you>
```

Port 445 is allowed only from `100.64.0.0/10` (the Tailscale range). Your router
is untouched; nothing is exposed to the internet.

## 2. Move your game folders onto E:  (once)

```
powershell -File E:\rdp-kit\adopt-local.ps1 -DryRun    # see what it would move
powershell -File E:\rdp-kit\adopt-local.ps1            # do it
```

Close Minecraft / Modrinth / Horizon first. It moves each folder to E: and
leaves a **junction** behind, so the path stays the same and your own PC keeps
working exactly as before — but now the runner and your PC read the same bytes.
No copying, no upload, no waiting.

It handles:

| Folder | Size on your pc |
|---|---|
| `.minecraft` | 3.0 GB |
| `ModrinthApp\profiles` | 18.5 GB |
| `ModrinthApp\meta` | 4.2 GB |
| `ModrinthApp\store` | 3.0 GB |
| `horizon-launcher` | 1.6 GB |

## 3. Three secrets

Repo -> Settings -> Secrets and variables -> Actions

| Name | Value |
|---|---|
| `SMB_PASSWORD` | the password from step 1 |
| `RDP_PASSWORD` | the password you log into the runner with |
| `TAILSCALE_AUTHKEY` | a Tailscale key, type **Ephemeral** |

## 4. Drop the workflow in and run it

`E:\rdp-kit\rdp-workflow.yml` -> `.github/workflows/rdp.yml`, commit, run.

---

## The user name is `util` on purpose

Modrinth's `app.db` and most launcher configs store absolute paths like
`C:\Users\util\AppData\Roaming\...`. If the runner's account is called `RDP`,
every one of those paths is wrong on the runner and your instances show up
broken. So the runner creates an account named `util` too, same path, same data.

## What gets copied, and what does not

**Every 5 minutes** (`FOLDERS`)

`Desktop` `Documents` `Downloads` `Pictures` `Videos` `Music`
`AppData\Roaming\Spotify` · `AppData\Roaming\Code\User` · `.ssh` · `.gitconfig`

**Once at boot, once at the end** (`HEAVY`)

| Path | Why |
|---|---|
| `AppData\Roaming\Mozilla` | Firefox profile — logins and cookies survive |
| `AppData\Roaming\Limyrx` | your launcher's config (103 MB) |
| `AppData\Roaming\ModrinthApp\app.db` | instance list + accounts (140 MB) |
| `AppData\Roaming\ModrinthApp\app.db-wal` | SQLite write-ahead log, if present |

`app.db` cannot live on the share: SQLite in WAL mode uses a shared-memory
segment (`-shm`) that does not work over SMB. It stays local and gets copied
around the session instead.

**Never copied — junctioned to `Z:` at logon**

| Runner path | Points at |
|---|---|
| `%APPDATA%\.minecraft` | `E:\RDP\files\minecraft` |
| `%APPDATA%\ModrinthApp\profiles` | `E:\RDP\files\modrinth\profiles` |
| `%APPDATA%\ModrinthApp\meta` | `E:\RDP\files\modrinth\meta` |
| `%APPDATA%\ModrinthApp\store` | `E:\RDP\files\modrinth\store` |
| `%APPDATA%\horizon-launcher` | `E:\RDP\files\horizon-launcher` |

`Z:` itself is the live share (`E:\RDP\files`), so anything you drop there is
on your disk instantly.

---

## Browser logins: Firefox works, Chrome cannot

Chrome and Edge encrypt their cookie database with a key in
`User Data\Local State`, sealed with **DPAPI**, which is bound to the Windows
user's SID. The runner builds a new account every run, so the old key cannot be
unsealed. Copying `User Data` gets you bookmarks, extensions and settings — the
sites will still log you out.

Firefox keeps logins in `logins.json` + `key4.db` inside the profile, with no
OS-bound key. Copy the profile and the sessions come with it. That is why
`AppData\Roaming\Mozilla` is in `HEAVY`.

Chrome with Sync signed in: passwords and bookmarks survive, session cookies do not.

---

## Apps

`Modrinth App` installs itself from its GitHub release (`Modrinth.App_x.y.z_x64-setup.exe`,
run with `/S`). Anything else: drop the installer `.exe` in `E:\RDP\installers`
and the workflow runs it before the session starts. Inno Setup installers want
`/VERYSILENT` instead of `/S`.

Cracked launchers: put the installer in `E:\RDP\installers` yourself. I am not
going to wire a download for one. Their data is under `AppData\Roaming\<Name>`
— add that folder to `HEAVY` and their instances survive.

---

## Things that will bite you

**The PC has to be awake.** Otherwise step 4 retries for 2.5 minutes and fails
with `cannot reach \\100.120.215.94\RDP`.

```powershell
powercfg /change standby-timeout-ac 0
powercfg /change hibernate-timeout-ac 0
```

**Close the launcher and browser before you end the session.** `app.db`,
`cookies.sqlite` and `places.sqlite` are locked while their app runs, so the
final copy skips them.

**Deletions do not propagate.** `robocopy /E` adds and overwrites, never deletes
on E:. Swap `/E` for `/MIR` in `sync.ps1` if you want mirroring — but then a bad
restore can delete real files.

**Games on `Z:` load slower.** Every asset read is a network round trip instead
of a disk read. It costs a few extra seconds at start-up; it is the price of not
copying 30 GB twice per run.

**If the tailnet IP changes**, edit `PC:` at the top of the workflow.
