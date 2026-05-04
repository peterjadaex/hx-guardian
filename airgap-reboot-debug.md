# Airgap dashboard — "localhost:8000 not loadable after restart"

Debug summary, 2026-04-25. Captures the full investigation, what is now fixed in the working tree, and what is still open.

---

## TL;DR

The original report ("localhost:8000 dies after every reboot") turned out to be **three separate problems stacked on top of each other**, not one. We fully diagnosed and fixed two; the third still needs one more diagnostic run on the airgap to pinpoint, but we already know the right shape of the fix.

| # | Problem | Status |
|---|---------|--------|
| 1 | `pgrep` reports every `hxg-*` daemon **doubled** after reboot | **Fixed in working tree.** Wrapper scripts now `exec` the binary. |
| 2 | `install.sh` cleanup only knew the four hardcoded labels and `/Library/LaunchDaemons/` — couldn't drain stray `LaunchAgents` or older labels | **Fixed in working tree.** Cleanup is now label-wildcard and covers Agents + user home. |
| 3 | After reboot, the server is **alive and bound on :8000** but the entire uvicorn event loop is wedged — *every* request (including the React SPA itself) hangs forever | **Diagnosed but root cause not yet pinpointed.** Real fix candidates known. Needs a 3-line `sample` capture from the airgap to confirm which frame is stuck. |

---

## 1. Symptom

After every reboot of the airgap Mac:
- Browser at `http://localhost:8000` shows a blank / spinning page indefinitely.
- `curl http://127.0.0.1:8000/api/health` times out, even with `--max-time 30`.
- `lsof -iTCP:8000 -sTCP:LISTEN` confirms `hxg-server` is bound on the port.
- `/Library/Logs/hxguardian-server-error.log` says `running on 127.0.0.1:8000` (i.e. the server *thinks* it started cleanly).
- `pgrep -lf 'hxg-'` reported **8 processes** (4 daemons × 2). Originally suspected as duplicate daemons.

Restarting the daemon manually after login (`launchctl kickstart -k system/com.hxguardian.server`) was the only known way to recover.

---

## 2. Environment

- macOS airgap device.
- `hx-guardian` installed via `sudo zsh app/install.sh` from the SD-card transfer bundle.
- Four LaunchDaemons under `/Library/LaunchDaemons/`:
  - `com.hxguardian.server` — runs as the operator user, FastAPI + React SPA on `127.0.0.1:8000`.
  - `com.hxguardian.runner` — runs as **root**, listens on Unix socket `/var/run/hxg/runner.sock`.
  - `com.hxguardian.usbwatcher`, `com.hxguardian.shellwatcher` — root, audit watchers.
- Architecture: server speaks newline-JSON over the Unix socket to the runner for any privileged action. The socket exists for **privilege separation** — see §6 below.

---

## 3. Investigation timeline

What was checked, in the order it surfaced, and the conclusion drawn at each step.

### 3.1 First glance — `pgrep` showed 8 processes, `lsof` showed 1 listener

Hypothesis: "two plists must be loading the same daemons → port :8000 is a race."
Disproved by reading [app/install.sh](app/install.sh) wrapper definitions at lines 118-149:

```zsh
cat > "$HXG_BIN/run-hxg-server" << EOF
#!/bin/zsh
export HOME="/Users/$ACTUAL_USER"
...
cd "$HXG_BIN/hxg-server"
"$HXG_BIN/hxg-server/hxg-server"   # ← no 'exec'
EOF
```

The wrapper invoked the binary **without `exec`**, so each daemon ran as `/bin/zsh …/run-hxg-NAME` parent + the actual binary child. Both processes have `hxg-` in their command line, so `pgrep -f hxg-` counts both. **The 2x count was a false alarm — one zsh wrapper plus one real binary, not two daemons.** Only one binary was listening on :8000 because there only ever was one.

The duplicate-detection check that was added in the uncommitted [app/start.sh:71-76](app/start.sh#L71-L76) used `pgrep -f` and therefore **fired on this false positive every single boot** — chasing its own tail.

### 3.2 Process state on the airgap (real data)

```
pgrep -x hxg-server   → 2929 (alive, single PID)
pgrep -x hxg-runner   → 2924 (alive, single PID)
lsof -iTCP:8000       → 2929 holding 127.0.0.1:8000 LISTEN
ls /var/run/hxg/runner.sock → exists, mode srw-rw-----
```

So the daemons are healthy and the socket file is present. Not a "dead daemon" or "missing socket" problem.

### 3.3 The decisive test — `curl -v --max-time 5`

Result: **`Operation timed out after 5000 ms`**.

On loopback, TCP handshake takes microseconds. A 5s timeout while `lsof` shows the port bound means TCP connects, but the application never produces an HTTP response. **The app is wedged on the request path, not on the network path.** This rules out:
- Safari rules (curl bypasses Safari).
- macOS Application Firewall (loopback is exempt by design).
- IPv4/IPv6 mismatch (we tested `127.0.0.1` directly).
- Server crash (PID still alive, port still bound).

### 3.4 Is the runner alive?

Tested with raw nc:
```
echo '{"action":"ping"}' | nc -U /var/run/hxg/runner.sock -w 5
→ {"req_id":"","pong":true,"done":true}
```

Runner replies instantly. **The runner's accept loop and request handler are fully healthy.** So the wedge is in the *server*, not the runner.

### 3.5 Reading the server's `/api/health` source

[app/backend/main.py:97-106](app/backend/main.py#L97-L106):

```python
@app.get("/api/health")
async def health():
    """Health check — also verifies runner connection."""
    from core.runner_client import ping
    runner_ok = await ping()
    return {"status": "ok", "runner_connected": runner_ok, ...}
```

`/api/health` is **not** a trivial liveness check — it makes an RPC over the Unix socket. [app/backend/core/runner_client.py:33-43](app/backend/core/runner_client.py#L33-L43) uses a hardcoded **5s connect-timeout + 3s read-timeout** ceiling, so even a healthy `ping()` can take up to ~8s in the worst case. We tested with `--max-time 30` and `/api/health` *still* never returned, so the wedge is below the explainable timeout ceiling.

### 3.6 Why the frontend is dark too

A common confusion. The React SPA is **not** served by a separate web server — it is served by the same `hxg-server` process. [app/backend/main.py:109-129](app/backend/main.py#L109-L129) mounts `/assets` and serves `index.html` for all non-API paths from the very same async event loop. Default uvicorn = 1 worker + 1 asyncio loop. **A single blocking call anywhere on the loop freezes every route — API endpoints and static files alike.** That is why the dashboard appears completely dead, not just one feature.

### 3.7 Scheduler hypothesis ruled out

Briefly suspected `_run_scheduled_scan` could fire at boot and wedge the loop with a sync DB call. User confirmed **no schedules are configured**, so APScheduler has no jobs to run. Eliminated.

### 3.8 Where the investigation paused

The remaining test would be `sudo /usr/bin/sample 2929 5 -file /tmp/s.txt` followed by reading the `Call graph:` section, which names the exact function the event loop is parked in. That trace plus the file/line numbers in the existing code is enough to identify the root cause precisely. **This is the one open data point.**

---

## 4. Root causes identified

### Root cause A (confirmed, fixed in this session)
**Wrapper scripts in [app/install.sh:118-149](app/install.sh#L118-L149) did not `exec` the binary**, leaving a zsh parent process around forever. Caused phantom 2x duplicate counts and triggered a misleading "stray plist" warning in start.sh that sent us chasing a non-existent duplicate-daemon problem.

### Root cause B (confirmed, fixed in this session)
**[app/install.sh](app/install.sh) cleanup was hardcoded to four labels and one directory** (`/Library/LaunchDaemons/`). Could not drain a stray LaunchAgent, an old label from a prior install, or any future renamed service. Defensively brittle.

### Root cause C (the actual reboot bug — diagnosed, root frame not yet pinpointed)
**The uvicorn event loop wedges after a fresh boot.** Confirmed signature:
- TCP accepts (kernel-level) → handler dispatches → request never produces a response.
- Server, runner, and socket are all individually healthy.
- Only manifests after reboot, not after `launchctl kickstart -k` (likely — needs confirmation).

The "only after reboot" pattern strongly suggests a **boot-order race**: server and runner plists both have `RunAtLoad=true` with no inter-dependency, so they start in parallel. If the server's first interaction with the runner socket happens in a window where the runner has bound the socket file but is not yet `accept()`-ing, the server-side `asyncio.open_unix_connection(..., timeout=5.0)` may end up in a state that wedges the connection but never lets the loop progress. The 5s timeout in [runner_client.py:35](app/backend/core/runner_client.py#L35) is a smell — it would never need to be that high on a healthy loopback socket; it was set that high specifically because someone observed slow connects, which is consistent with a startup race.

The `sample` capture would either confirm this (frame parked in `asyncio.open_unix_connection` or `asyncio.wait_for`) or point at something else (a sync DB call from `init_db`, a stuck import).

---

## 5. Fixes already applied (uncommitted, working tree)

Three edits, all in `app/`:

### 5.1 `exec` the binary in every wrapper — [app/install.sh:118-149](app/install.sh#L118-L149)

All four wrappers (`run-hxg-server`, `run-hxg-runner`, `run-hxg-usb-watcher`, `run-hxg-shell-watcher`) now end with `exec "$HXG_BIN/<name>/<name>"` instead of just `"$HXG_BIN/<name>/<name>"`. Result: each daemon is one PID, not two.

### 5.2 Tighten the duplicate-detection heuristic — [app/start.sh:71-76](app/start.sh#L71-L76)

`pgrep -f "$bin"` → `pgrep -x "$bin"`. Exact-name match, so the zsh wrapper's command line cannot be miscounted as a copy of the binary. The warning now only fires on a real duplicate.

### 5.3 Make cleanup label-agnostic — [app/install.sh:32-39, 53-60](app/install.sh#L32-L60)

Replaced the hardcoded four-label `bootout` and `rm -f` lines with:
- A loop that drains any `com.hxguardian.*` registration from launchd's system domain.
- Wildcard `rm -f` covering `/Library/LaunchDaemons/`, `/Library/LaunchAgents/`, and `/Users/$ACTUAL_USER/Library/LaunchAgents/`.

These edits address Root causes A and B. They do **not** address Root cause C — the event-loop wedge is independent.

---

## 6. Architecture context — why the Unix socket exists

User asked "can we just remove the socket?" — short answer no, here's why.

- **`hxg-server` runs as the operator user**, not root. It is the HTTP attack surface (parses JSON, runs Python, talks to a browser). If something there is exploited, the attacker gets a normal user's privileges.
- **`hxg-runner` runs as root** and refuses to start otherwise ([hxg_runner.py:414-416](app/backend/hxg_runner.py#L414-L416)). It executes the actual scan/fix shell scripts (`pwpolicy`, `profiles install`, hardening rules) which all require root.
- **The socket is the privilege boundary.** Only allowlisted actions cross it ([hxg_runner.py:174-180](app/backend/hxg_runner.py#L174-L180) checks every rule against a manifest). Server cannot ask the runner to do anything not in `manifest.json`.

If the socket is removed, either the HTTP-facing server runs as root (one Python bug = full machine compromise) or it cannot run any rule at all. Neither is acceptable for a security-hardening tool. **The right fix is to make the socket coupling robust, not to remove it.**

---

## 7. Recommended fixes for Root cause C (not yet applied — pending sample output)

In priority order. Do **all** of (1)-(3) regardless of what the sample shows; they are good engineering. Do (4) once the sample confirms the boot-order race.

### 7.1 Decouple `/api/health` from the runner — [app/backend/main.py:97-106](app/backend/main.py#L97-L106)

A liveness check should report whether *this* server is alive. It should not collapse the dashboard if a downstream RPC is slow. Replace with:

```python
@app.get("/api/health")
async def health():
    return {"status": "ok", "version": "1.0.0"}
```

Add a separate `/api/runner/status` route for runner liveness, with its own bounded timeout. The browser can call both and render runner status as a UI badge that turns red when `runner` is unreachable — without taking the whole UI with it.

### 7.2 Shrink the timeouts in [runner_client.py:33-43](app/backend/core/runner_client.py#L33-L43)

The hardcoded 5s connect-timeout for a *loopback Unix socket* is 10,000× too generous. A healthy loopback connect is under 1 ms. Drop to 500 ms. A genuine wedge then surfaces as a fast `RunnerError`, not a frozen request that takes 8s to fail.

### 7.3 Wrap every runner call in an outer `asyncio.wait_for(..., timeout=...)` on the server side

Belt-and-suspenders: even if a future code path forgets a timeout, no single runner call can park the event loop indefinitely.

### 7.4 Make the server plist depend on the runner being ready

If the sample confirms the wedge is in `open_unix_connection` at boot, fix the race directly. Two viable shapes:
- **Boot ordering**: the server's `run-hxg-server` wrapper waits for `/var/run/hxg/runner.sock` to be `connect()`-able before exec'ing the server binary (a tiny shell loop with a 30s cap).
- **Application-level retry**: `runner_client._send_recv_lines` wraps the connect in a short retry loop with backoff (e.g. 5× over 2s). If the runner isn't ready yet, we wait a beat and retry instead of hanging on a single attempt.

Either resolves the boot race cleanly without touching the privilege boundary. The retry approach is generally more robust because it tolerates transient runner restarts later in life, not just at boot.

---

## 8. Open items / next steps

1. **Get the sample output from the airgap** to lock down Root cause C:
   ```
   sudo /usr/bin/sample 2929 5 -file /tmp/s.txt 2>&1 >/dev/null
   sudo /usr/bin/sed -n '/Call graph:/,/Binary Images:/p' /tmp/s.txt | /usr/bin/head -80
   ```
   Look for the parked frame: `asyncio.open_unix_connection`, `wait_for`, `init_db`, or something else. The answer points directly at which §7 fix to apply first.

2. **Confirm the "only after reboot" claim** with `launchctl kickstart -k system/com.hxguardian.server`:
   ```
   sudo /bin/launchctl kickstart -k system/com.hxguardian.server
   sleep 5
   time /usr/bin/curl -sS --max-time 30 http://127.0.0.1:8000/api/health
   ```
   If this returns instantly after kickstart, Root cause C is definitely a **boot-time race**, and §7.4 is the targeted fix. If it still hangs after kickstart, the wedge is persistent and §7.1-7.3 mitigate it while we keep digging.

3. **Decide whether to commit the §5 edits separately**, or bundle them with the §7 changes once those are applied. They're orthogonal, so a separate commit makes the duplicate-process fix easy to backport.

4. **Roll the fix to the airgap**:
   ```
   zsh app/build.sh                  # dev machine, rebuild binaries
   zsh app/prepare_sd_card.sh        # rebuild transfer bundle
   # carry SD card to airgap
   sudo zsh app/install.sh           # cleanup is now wildcard, safe to rerun
   ```
   Then reboot and verify with the diagnostics in §9.

---

## 9. Diagnostic command reference

For future debugging, here are the commands that proved most useful, grouped by what they answer.

**Process / port state:**
```
/usr/bin/pgrep -x hxg-server hxg-runner hxg-usb-watcher hxg-shell-watcher
sudo /usr/sbin/lsof -nP -iTCP:8000 -sTCP:LISTEN
sudo ls -la /var/run/hxg/runner.sock
```

**Runner direct test (bypasses the server):**
```
echo '{"action":"ping"}' | /usr/bin/nc -U /var/run/hxg/runner.sock -w 5
```

**Server endpoint test (with enough patience to outwait timeouts):**
```
time /usr/bin/curl -sS --max-time 30 http://127.0.0.1:8000/api/health
```

**Verbose curl to distinguish refused vs hung:**
```
/usr/bin/curl -v --max-time 8 http://127.0.0.1:8000/api/health 2>&1 | head -25
```

**Stack trace of a stuck server:**
```
sudo /usr/bin/sample $(pgrep -x hxg-server) 5 -file /tmp/s.txt
sudo sed -n '/Call graph:/,/Binary Images:/p' /tmp/s.txt | head -80
```

**Logs:**
```
sudo /usr/bin/tail -n 80 /Library/Logs/hxguardian-server-error.log
sudo /usr/bin/tail -n 40 /Library/Logs/hxguardian-runner-error.log
sudo /usr/bin/tail -n 40 /Library/Logs/hxguardian-runner.log
```

**Daemon state (last exit reason, throttle status):**
```
sudo /bin/launchctl print system/com.hxguardian.server | head -60
sudo /bin/launchctl print system/com.hxguardian.runner | head -60
```

**Restart just the server (no reboot needed):**
```
sudo /bin/launchctl kickstart -k system/com.hxguardian.server
```

---

## 10. Escape hatch — disable launchd socket activation

If launchd socket activation misbehaves on this device (e.g. the runner never spawns, the socket file has wrong perms, or the ctypes path failed inside the frozen binary), an operator can fall back to the pre-fix bind/listen behavior **without an SD card or rebuild**:

1. Restore the previous plist from the install-time snapshot:
   ```
   ls -t /Library/LaunchDaemons/com.hxguardian.runner.plist.bak.* | head -1
   sudo cp /Library/LaunchDaemons/com.hxguardian.runner.plist.bak.<TIMESTAMP> \
           /Library/LaunchDaemons/com.hxguardian.runner.plist
   ```
   *Or* hand-edit the active plist: remove the `<key>Sockets</key>` block, set `RunAtLoad` to `<true/>`, set `KeepAlive` to `<true/>`.

2. Reload the daemon:
   ```
   sudo /bin/launchctl bootout system/com.hxguardian.runner
   sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.hxguardian.runner.plist
   ```

3. Verify the runner is up:
   ```
   echo '{"action":"ping"}' | /usr/bin/nc -U /var/run/hxg/runner.sock -w 5
   ```

The runner's `run_server()` automatically falls back to manual bind/listen if `launch_activate_socket` is unavailable or returns no fds, so no code change is needed — just the plist edit. Logs at `/Library/Logs/hxguardian-runner.log` will show `"listening on … (dev mode)"` instead of `"inherited socket from launchd"`, confirming the fallback path.
