# CI/CD and build fixes (living document)

This document records all changes made to get the GitHub Actions Windows build passing, starting from commit `3d32139512cc4576b105682c3579f18fe0d534e4`. It is updated whenever new fixes or adjustments are needed.

---

## 1. GitHub Actions workflows

**Files:** `.github/workflows/ci-cd.yml`, `pr-test.yml`, `build-on-request.yml`

### 1.1 Runners

- **Windows:** `windows-2019` → `windows-2022`.
- **Mac:** `macos-11` → `macos-latest`.

### 1.2 Artifact upload/download (v2 → v4)

- **Why:** `actions/upload-artifact@v2` and `download-artifact@v2` are deprecated.
- **Change:** Switched to `actions/upload-artifact@v4` and `download-artifact@v4`.
- **Detail:** v4 does not allow multiple jobs to upload to the same artifact name. Each job now uses a **unique artifact name** (e.g. `Binaries-windows`, `Binaries-mac`). Download steps use `pattern: Binaries-*` and `merge-multiple: true` to collect them.

### 1.3 Removed Android and Linux builds

- **Why:** Focus on Windows; simplify pipelines.
- **Change:** Android and Linux/Ubuntu jobs removed from all three workflows. Release/Test jobs’ `needs` and artifact lists updated accordingly (e.g. `needs: [Windows, Mac]`). Robocopy and artifact paths no longer reference Android/Linux outputs. Optional artifacts (e.g. `otclient_mac`) use `if-no-files-found: warn` where appropriate.

### 1.4 Mac job allowed to fail

- **Why:** Keep Windows as the primary gate; Mac can be best-effort.
- **Change:** Mac job has `continue-on-error: true` in all three workflows.

### 1.5 Windows vcpkg cache

- **Why:** Avoid re-downloading and re-building vcpkg dependencies on every run.
- **Change:**
  - **Restore:** Step `vcpkg-cache-restore` uses `actions/cache/restore@v4` to restore the **entire** `${{ runner.workspace }}/vcpkg` directory. Cache key includes vcpkg commit: `vcpkg-win-x86-static-4bc3a47c7a63506e215e04e1473368adbaea6c27-v3`, with restore-keys for partial matches.
  - **Skip install on hit:** The “Run vcpkg” step has `if: steps.vcpkg-cache-restore.outputs.cache-hit != 'true'`.
  - **Save:** Step `actions/cache/save@v4` runs only when `steps.vcpkg-cache-restore.outputs.cache-hit != 'true' && steps.run-vcpkg.outcome == 'success'`.
- **Note:** The run-vcpkg step uses `doNotCache: true` so the action’s built-in cache is not used; we rely on the explicit restore/save steps above.

### 1.6 vcpkg version (Windows)

- **Why:** Old vcpkg commit had broken MSYS2 mirrors / download issues.
- **Change:** Windows triplet uses vcpkg commit `4bc3a47c7a63506e215e04e1473368adbaea6c27` (replacing `3b3bd424827a1f7f4813216f6b32b6c61e386b2e`). Set via `vcpkgGitCommitId` in the run-vcpkg step.

### 1.7 vcpkg integrate (Windows)

- **Why:** Path format on Windows.
- **Change:** “Integrate vcpkg” step uses backslashes: `${{ runner.workspace }}\vcpkg\vcpkg integrate install`.

### 1.8 boost-process removed from vcpkg

- **Why:** Boost.Process v2 (from Boost 1.90 in the updated vcpkg) caused Windows build errors (`startup_info`, `child`, `args`, `DeleteProcThreadAttributeList`). We replaced its usage with native platform APIs.
- **Change:** Removed `boost-process` from the vcpkg package lists in all three workflows (Windows and, where present, Mac). Also removed from the README install line.

### 1.9 macOS vcpkg cache (same pattern as Windows)

- **Why:** Mac job was failing with “fatal: not a git repository” when `run-vcpkg` tried to detect the vcpkg commit from the directory (empty or not a clone), and “Install/Update ports” could fail with exit code 1. Applying the same explicit cache as Windows avoids re-running vcpkg on cache hit and avoids relying on the action’s git detection.
- **Change:** In all three workflows, the Mac job now has:
  - **Restore:** “Restore vcpkg cache” using `actions/cache/restore@v4` with key `vcpkg-mac-x64-osx-761c81d43335a5d5ccc2ec8ad90bd7e2cbba734e-v1`, path `${{ runner.workspace }}/vcpkg`, and restore-keys for partial matches.
  - **Skip install on hit:** “Run vcpkg” has `if: steps.vcpkg-cache-restore.outputs.cache-hit != 'true'`.
  - **doNotCache: true** on the run-vcpkg step so the action does not use its built-in cache (which depended on git in the vcpkg directory).
  - **Save:** “Save vcpkg cache” runs only when cache was not restored and run-vcpkg succeeded.
- **Result:** On cache hit, the full vcpkg tree (including installed ports) is restored and run-vcpkg is skipped, so no git repo is required. On cache miss, vcpkg runs once; if it succeeds, the next run will use the cache. If “Install/Update ports” still fails on first run, check the workflow log for the failing port and fix or pin as needed.

---

## 2. Application code: Boost version compatibility

**Context:** vcpkg was updated to a newer commit, bringing in Boost ~1.90. The codebase expected an older Boost (~1.78). The following changes make the code work with the newer Boost.

### 2.1 Boost.Asio: io_service → io_context

- **Why:** `io_service` was removed/renamed in favor of `io_context`.
- **Files changed:**
  - `src/framework/pch.h`: `#include <boost/asio/io_service.hpp>` → `#include <boost/asio/io_context.hpp>`.
  - `src/framework/net/connection.cpp`: `asio::io_service g_ioService` → `asio::io_context g_ioService`.
  - `src/framework/net/connection.h`: (signatures unchanged; implementation uses io_context).
  - `src/framework/net/protocol.cpp`: `extern asio::io_service g_ioService` → `extern asio::io_context g_ioService`.
  - `src/framework/net/server.cpp`: same extern change.
  - `src/framework/http/session.h`: `io_service&` → `io_context&` (member and ctor).
  - `src/framework/http/websocket.h`: `io_service&` → `io_context&` (member and ctor).

### 2.2 Boost.Asio: resolver API

- **Why:** Resolver API changed; the old iterator-based API was removed.
- **connection.cpp/h:**
  - Removed `resolver::query`; use `m_resolver.async_resolve(host, port_string, ...)`.
  - `onResolve` and `internal_connect` now take `resolver::results_type` (or `const results_type&`). Connect via `asio::async_connect(m_socket, endpoints, lambda)`; no single-iterator `async_connect(*iterator)`.
- **session.cpp/h:** `on_resolve(ec, iterator)` → `on_resolve(ec, endpoints)`; check `endpoints.empty()`; connect to `endpoints.begin()->endpoint()`.
- **websocket.cpp/h:** Same: `results_type`, `endpoints.begin()->endpoint()`, then pass endpoint to `async_connect`.
- **proxy_client.cpp:** `endpoint = boost::asio::ip::tcp::endpoint(*results)` → `endpoint = results.begin()->endpoint()`.

### 2.3 Boost endian (no Asio internal APIs)

- **Why:** Avoid using `boost::asio::detail::socket_ops::host_to_network_long` and similar internals.
- **connection.cpp:** `#include <boost/endian/conversion.hpp>`; `host_to_network_long(...)` → `boost::endian::native_to_big(...)`.
- **src/framework/stdext/net.cpp:** `#include <boost/endian/conversion.hpp>`; `network_to_host_long` → `big_to_native`, `host_to_network_long` → `native_to_big` (including in `listSubnetAddresses`).

### 2.4 Other Boost.Asio 1.90 API changes (io_context, timer, buffer, address_v4)

- **io_context:** `reset()` was removed; use `restart()` to clear the stopped state before calling `poll()` again (e.g. in `connection.cpp` `poll()`).
- **basic_waitable_timer:** `expires_from_now(duration)` was removed; use `expires_after(duration)` everywhere (connection.cpp, proxy_client.cpp). Also `cancel(ec)` → `cancel()` (see BUILD-FIX-LOG Fix 1).
- **buffer_cast:** `boost::asio::buffer_cast<T>(buf)` was removed. To get a pointer from a streambuf’s data, use `boost::asio::buffers_begin(m_inputStream.data())` and then `&*it` (with a check for empty/recvSize if needed).
- **address_v4:** `to_ulong()` was removed; use `to_uint()` (returns `uint32_t`) in connection.cpp and stdext/net.cpp.
- **Timer cancel:** `cancel(ec)` → `cancel()` in session.cpp (Fix 1) and proxy_client.cpp (same pattern).

### 2.5 Full Boost usage audit (Boost 1.90)

All Boost-using sources have been checked for 1.90 compatibility. Summary:

| Area | Files | Status |
|------|--------|--------|
| **Asio (net)** | connection.cpp/h, server.cpp, protocol.cpp, declarations.h | §2.1–2.4 applied (io_context, resolver, timer, buffer, endian, address_v4). |
| **Asio (HTTP/WS)** | session.cpp/h, websocket.cpp/h, http.cpp/h | io_context, resolver results_type, timer cancel/expires_after, Beast field string_view→string; make_work_guard + executor_work_guard still valid in 1.90. |
| **Asio (proxy)** | proxy_client.cpp/h, proxy.cpp, proxy.h | resolver results_type, timer expires_after + cancel(), endpoint from results. |
| **Beast** | session.cpp, websocket.cpp, pch.h | Field access via .data()/.size(); timer cancel(); buffers_to_string, get_lowest_layer, async_read/write unchanged. |
| **Endian** | connection.cpp, stdext/net.cpp | boost::endian::native_to_big / big_to_native (§2.3, §2.4). |
| **Other Boost** | pch.h (system, asio, beast, algorithm/hex), stdext (algorithm, lexical_cast, uri), crypt.cpp/h (uuid, hash), otml (tokenizer), win32platform (algorithm), packet_player (algorithm::unhex), uitranslator (algorithm), string.cpp (algorithm) | No deprecated APIs used; algorithm, uuid, tokenizer, lexical_cast, functional/hash stable in 1.90. |
| **Removed** | Boost.Process | Replaced with platform spawnProcessAndWait (§3). |

No remaining uses of: `io_service`, `resolver::query`, resolver iterator, `socket_ops`, `expires_from_now`, `buffer_cast`, `address_v4::to_ulong`, Beast field `.to_string()`, or timer `.cancel(ec)`.

---

## 3. Replacing Boost.Process with platform APIs

**Why:** Boost.Process v2 in Boost 1.90 caused compile errors on Windows (e.g. in `default_launcher.hpp`, `stdio.hpp`). We removed the dependency and use native process launch instead.

### 3.1 New platform API: spawnProcessAndWait

- **Declaration:** `src/framework/platform/platform.h`  
  - `bool spawnProcessAndWait(const std::string& process, const std::vector<std::string>& args, int waitSeconds, int* exitCode = nullptr);`  
  - Semantics: launch process; if `waitSeconds > 0`, wait up to that many seconds; if `exitCode` is non-null and the process exits in time, set `*exitCode`. Returns true if the process was started.

- **Implementations:**
  - **Windows:** `src/framework/platform/win32platform.cpp` — Build command line (exe quoted + args quoted), `CreateProcessW`, optionally `WaitForSingleObject(pi.hProcess, ms)` + `GetExitCodeProcess`, then `CloseHandle` on process and thread.
  - **Unix:** `src/framework/platform/unixplatform.cpp` — `fork` + `execv` (with `std::vector<char*> cargs`), then if `waitSeconds > 0` use `waitpid(pid, &status, WNOHANG)` in a loop with `sleep(1)` until timeout or exit; set `*exitCode` via `WEXITSTATUS(status)` when `WIFEXITED(status)`. Added `#include <sys/wait.h>`.
  - **Android:** `src/framework/platform/androidplatform.cpp` — Stub that returns `false` (parameters unused).

### 3.2 Call sites updated

- **application.cpp**
  - Removed `#if not(defined(ANDROID) || defined(FREE_VERSION))` block that included `#include <boost/process.hpp>`.
  - `restart()`: `boost::process::child c(g_resources.getBinaryName());` + `wait_for` + `detach` replaced with `if (!g_platform.spawnProcessAndWait(g_resources.getBinaryPath(), {}, 1, nullptr)) g_logger.fatal(...);` then `quick_exit()`.
  - `restartArgs(args)`: same pattern with `g_platform.spawnProcessAndWait(g_resources.getBinaryPath(), args, 1, nullptr)`.

- **resourcemanager.cpp**
  - Removed the `#if` block that included `#include <boost/process.hpp>`.
  - Replaced `boost::process::child c(binary.string());` + `wait_for(5s)` + `exit_code()` + `detach()` with `int exitCode = -1; g_platform.spawnProcessAndWait(binary.string(), {}, 5, &exitCode)`; if process exited in time return `exitCode == 0`, else return `true`.

### 3.3 Binary path for restart

- **resourcemanager.h:** Added `std::string getBinaryPath() { return m_binaryPath.string(); }` (non-Android).
- **application.cpp:** Uses `g_resources.getBinaryPath()` for both `restart()` and `restartArgs()`.

### 3.4 vcpkg and docs

- Removed `boost-process` from workflow vcpkg package lists and from the README install command (see §1.8).

---

## 4. Version / context summary

| Item          | Before (commit 3d32139)     | After (current)                |
|---------------|-----------------------------|---------------------------------|
| vcpkg commit  | 3b3bd424827a1f7f4813216f6b32b6c61e386b2e | 4bc3a47c7a63506e215e04e1473368adbaea6c27 |
| Boost         | ~1.78                       | ~1.90 (from vcpkg)              |
| Windows runner| windows-2019                | windows-2022                    |
| Mac runner    | macos-11                    | macos-latest                    |
| Artifacts     | upload/download v2          | v4, unique names, merge-multiple|
| Process API   | Boost.Process               | Platform `spawnProcessAndWait`  |

---

## 5. Commit history (oldest to newest)

All changes since baseline `3d32139512cc4576b105682c3579f18fe0d534e4`:

| Commit     | Message |
|-----------|--------|
| `f3addc1` | use up to date builders |
| `0c103ba` | fix(ci): upgrade to actions/upload-artifact@v4 and download-artifact@v4 |
| `ef3b6a1` | ci: drop Android/Linux, optional Mac, fix Windows vcpkg cache |
| `8241963` | ci: update Windows vcpkg to latest for working MSYS2 mirrors |
| `0fa234d` | ci: re-enable vcpkg cache in GHA for faster runs |
| `083249c` | fix: use Boost.Asio io_context instead of deprecated io_service |
| `9206b94` | macos latest |
| `2fa1769` | ci: add deterministic vcpkg cache restore/save for Windows |
| `5b516fa` | refactor(boost): migrate Asio APIs from 1.78-era to 1.90 |
| `5a79e62` | ci: cache full vcpkg dir and skip install on cache hit |
| `f4956b8` | Replace Boost.Process with platform spawnProcessAndWait; remove boost-process from vcpkg |

---

## 6. Files touched (summary)

- **Workflows:** `.github/workflows/build-on-request.yml`, `ci-cd.yml`, `pr-test.yml`
- **Docs:** `README.md` (vcpkg install line)
- **Core:** `src/framework/core/application.cpp`, `resourcemanager.cpp`, `resourcemanager.h`
- **Net:** `src/framework/net/connection.cpp`, `connection.h`, `protocol.cpp`, `server.cpp`
- **HTTP:** `src/framework/http/session.cpp`, `session.h`, `websocket.cpp`, `websocket.h`
- **Other:** `src/framework/pch.h`, `src/framework/proxy/proxy_client.cpp`, `src/framework/stdext/net.cpp`
- **Platform:** `src/framework/platform/platform.h`, `win32platform.cpp`, `unixplatform.cpp`, `androidplatform.cpp`

---

## 7. What to do next (if something breaks)

1. **Windows build fails again**
   - Check if new errors are from Boost (Asio, Beast, Process). If Process reappears, ensure no `#include <boost/process.hpp>` and no `boost::process::child` / `args` remain.
   - If vcpkg or MSYS2 downloads fail, consider updating the vcpkg commit or cache key.
   - If a different Boost component breaks, consider pinning or adapting the code and document it here.

2. **Mac build**
   - Mac is `continue-on-error: true`; fix only if you want Mac to be a hard gate. Document any Mac-specific vcpkg or build changes here.

3. **Artifacts / release**
   - If you add a new platform or job, give it a unique artifact name and add it to the merge pattern and any release/robocopy steps. Update this doc.

4. **Updating this document**
   - Add a new numbered section (or subsection) for each new category of fix. Keep “Version / context” (§4) and “Commit history” (§5) updated when you change vcpkg/Boost or add notable commits.

5. **One-off build errors (Beast, Asio, etc.)**
   - Individual fixes (e.g. string_view, timer API) are documented in ** [docs/BUILD-FIX-LOG.md](BUILD-FIX-LOG.md)**. Add new entries there and, if relevant, mention the fix here in §2 or §7.
