# Build fix log (post–CI baseline)

This document records individual build fixes applied after the initial CI/CD and Boost migration. Each entry is a discrete fix you can refer to or replicate. Append new fixes as they come.

---

## Fix 1: Boost.Beast / Asio API in `session.cpp` (Windows, Boost 1.90)

**Date:** 2025-03 (current)  
**Context:** Windows build failed with 3 errors in `src/framework/http/session.cpp` after the main Boost migration.

### Errors

1. **C2039: 'to_string': is not a member of 'boost::core::basic_string_view<char>'** (lines 125, 129)  
   HTTP field values in Beast are `boost::core::basic_string_view<char>` and do not have `.to_string()` in Boost 1.90.

2. **C2660: '...::cancel': function does not take 1 arguments** (line 218)  
   In Boost.Asio 1.90, `basic_waitable_timer::cancel()` has no parameters; the old `cancel(boost::system::error_code&)` overload was removed.

### Changes

**File:** `src/framework/http/session.cpp`

1. **Lines 125–126 (Content-Length)**  
   - Before: `m_result->size = atoi(msg["Content-Length"].to_string().c_str());`  
   - After: build a `std::string` from the field’s string_view, then use it:
     - `auto cl = msg["Content-Length"];`
     - `m_result->size = atoi(std::string(cl.data(), cl.size()).c_str());`

2. **Lines 129–130 (Location redirect)**  
   - Before: `location.to_string()`  
   - After: `std::string(location.data(), location.size())`  
   So the redirect URL is constructed from the string_view.

3. **Line 218 (timer cancel in onError)**  
   - Before: `m_timer.cancel(ec);`  
   - After: `m_timer.cancel();`  
   No error_code argument; `ec` is still used for `m_socket.close(ec)` only.

### Summary

| Issue              | Cause                          | Fix |
|--------------------|----------------------------------|-----|
| `to_string()` on field values | Beast uses string_view, no `to_string()` | `std::string(data(), size())` |
| `cancel(ec)` on timer         | Asio timer `cancel()` is now 0-arg      | `m_timer.cancel();` |

---

## Fix 2: LuaJIT / lbitlib — INT_MAX and luaL_newlib (Windows)

**Context:** Windows build failed in `src/framework/luaengine/lbitlib.cpp`: `INT_MAX` undeclared and `luaL_newlib` macro redefinition warning.

### Errors

1. **C2065: 'INT_MAX': undeclared identifier** (line 150)  
   The macro `lua_unsigned2number` uses `INT_MAX` (see line 143), but no standard header defining it was included.

2. **C4005: 'luaL_newlib': macro redefinition** (line 168)  
   The file defines a Lua 5.2–style `luaL_newlib` for compatibility; LuaJIT’s `lauxlib.h` already defines `luaL_newlib`, so the redefinition triggers a warning.

### Changes

**File:** `src/framework/luaengine/lbitlib.cpp`

1. **Include &lt;climits&gt;**  
   After the `extern "C"` block that includes the Lua/LuaJIT headers, add:
   ```c
   #include <climits>
   ```
   so `INT_MAX` is available when `lua_unsigned2number` is expanded.

2. **Guard luaL_newlib**  
   Only define the compatibility macro if LuaJIT did not already define it:
   - Before: `#define luaL_newlib(x, y) luaL_register(x, LUA_BIT32LIBNAME, y)`
   - After:
     ```c
     #ifndef luaL_newlib
     #define luaL_newlib(x, y) luaL_register(x, LUA_BIT32LIBNAME, y)
     #endif
     ```

### Summary

| Issue              | Cause                               | Fix |
|--------------------|--------------------------------------|-----|
| `INT_MAX` undeclared | No header defining `INT_MAX` included | `#include <climits>` |
| `luaL_newlib` redefinition | LuaJIT’s lauxlib.h already defines it | Wrap in `#ifndef luaL_newlib` |

---

## Fix 3: Remaining Boost.Asio API changes (connection, timer, buffer, address)

**Context:** Windows build failed in `connection.cpp` (and related) with multiple Boost 1.90 Asio API errors: `io_context::reset`, timer `expires_from_now`, `buffer_cast`, and `address_v4::to_ulong`.

### Errors

1. **C2039: 'reset': is not a member of 'boost::asio::io_context'** (connection.cpp line 57)  
   In Boost.Asio, `io_context` uses `restart()` instead of `reset()` to clear the stopped state.

2. **C2039: 'expires_from_now': is not a member of '...basic_waitable_timer<...>'** (connection.cpp lines 105, 117, 135, 157, 173, 190, 205)  
   In Boost.Asio 1.24+, the timer API was renamed: `expires_from_now(duration)` → `expires_after(duration)`.

3. **C2039: 'buffer_cast': is not a member of 'boost::asio'** (connection.cpp line 285)  
   `boost::asio::buffer_cast` was removed. Use `boost::asio::buffers_begin(stream.data())` and take the address of the first element (`&*it`) to get a pointer.

4. **C2039: 'to_ulong': is not a member of 'boost::asio::ip::address_v4'** (connection.cpp line 321, stdext/net.cpp)  
   In Boost.Asio, `address_v4::to_ulong()` was removed; use `to_uint()` instead (returns `uint32_t`).

### Changes

**File: `src/framework/net/connection.cpp`**

- **poll():** `g_ioService.reset()` → `g_ioService.restart()`.
- **Timers:** All `m_readTimer.expires_from_now(...)`, `m_delayedWriteTimer.expires_from_now(...)`, `m_writeTimer.expires_from_now(...)` → `expires_after(...)`.
- **onRecv:** Replace `boost::asio::buffer_cast<const char*>(m_inputStream.data())` with:
  ```cpp
  auto it = boost::asio::buffers_begin(m_inputStream.data());
  const char* header = recvSize > 0 ? &*it : nullptr;
  ```
- **getIp():** `ip.address().to_v4().to_ulong()` → `ip.address().to_v4().to_uint()`.

**File: `src/framework/proxy/proxy_client.cpp`**

- Both timer calls: `m_timer.expires_from_now(...)` → `m_timer.expires_after(...)`.
- In the destructor/lambda (line 40): `m_timer.cancel(ec)` → `m_timer.cancel()` (same as Fix 1; timer no longer takes an error_code).

**File: `src/framework/stdext/net.cpp`**

- **string_to_ip:** `address_v4.to_ulong()` → `address_v4.to_uint()`.

### Summary

| Issue | Cause | Fix |
|-------|--------|-----|
| `io_context::reset` | Removed in favor of `restart()` | `g_ioService.restart()` |
| `expires_from_now` | Renamed in Asio 1.24+ | `expires_after(duration)` |
| `buffer_cast` | Removed from Asio | `buffers_begin(stream.data())`, then `&*it` |
| `address_v4::to_ulong` | Removed | `address_v4.to_uint()` |

---

## Next fixes

*(Add new sections below as new build errors are fixed.)*
