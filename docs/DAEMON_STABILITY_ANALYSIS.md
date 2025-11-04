# i3pm Daemon Stability Analysis
## Root Cause Analysis - Sporadic Unresponsive Daemon

**Date**: 2025-11-04
**Issue**: Daemon becomes unresponsive, fails to respond to IPC requests, and requires SIGKILL to terminate

---

## Executive Summary

The i3pm daemon has **critical signal handling bugs** that cause it to become unresponsive and fail graceful shutdown. When systemd tries to stop the daemon (SIGTERM), the daemon hangs for 90 seconds until systemd forcefully kills it (SIGKILL).

**Key Findings:**
1. ❌ **Thread-unsafe signal handling** - Signal handlers call asyncio operations unsafely
2. ❌ **No shutdown timeouts** - Shutdown operations can hang indefinitely
3. ❌ **No timeout configuration** - Using systemd defaults (90s)
4. ⚠️ **Unexplained USR1 crash** - Daemon crashed with unhandled signal

---

## Evidence from Logs

### Timeout Failures (systemd had to SIGKILL)
```
Nov 04 14:44:00 - i3-project-daemon.service: State 'stop-sigterm' timed out. Killing.
Nov 04 16:06:28 - i3-project-daemon.service: State 'stop-sigterm' timed out. Killing.
```

### Unexplained Crash
```
Nov 04 16:30:51 - Main process exited, code=killed, status=10/USR1
```

### Current Configuration
```
TimeoutStopUSec=1min 30s    # 90 seconds before SIGKILL
WatchdogUSec=30s            # Expect watchdog ping every 30s
Restart=always              # Auto-restart on failure
Type=notify                 # Wait for READY=1 signal
```

---

## Critical Bug #1: Thread-Unsafe Signal Handling

### Location
`/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py:573-581`

### Current Code (BROKEN)
```python
def setup_signal_handlers(self) -> None:
    """Setup signal handlers for graceful shutdown."""

    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating shutdown...")
        self.shutdown_event.set()  # ❌ UNSAFE! Called from signal handler

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
```

### Problem
Signal handlers execute in a **synchronous, interrupt context** - they cannot safely call asyncio operations! When SIGTERM arrives:
1. Signal handler calls `self.shutdown_event.set()`
2. This is an asyncio Event method that modifies event loop state
3. If the event loop is in the middle of another operation, this causes:
   - Race conditions
   - Deadlocks
   - Undefined behavior
4. Daemon becomes unresponsive

### Correct Implementation
```python
def setup_signal_handlers(self) -> None:
    """Setup signal handlers for graceful shutdown."""

    def signal_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating shutdown...")
        # ✅ SAFE: Use call_soon_threadsafe for asyncio operations from signals
        loop = asyncio.get_event_loop()
        loop.call_soon_threadsafe(self.shutdown_event.set)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
```

**Why this works:**
- `call_soon_threadsafe()` is **designed** for calling asyncio from other threads/signals
- It safely schedules the operation to run on the event loop's next iteration
- No race conditions, no undefined behavior

---

## Critical Bug #2: No Shutdown Timeouts

### Location
`/etc/nixos/home-modules/desktop/i3-project-event-daemon/daemon.py:547-571`

### Current Code (RISKY)
```python
async def shutdown(self) -> None:
    """Graceful shutdown."""
    logger.info("Shutting down daemon...")

    if self.health_monitor:
        self.health_monitor.notify_stopping()

    # ❌ No timeout - can hang forever!
    await shutdown_project_switch_queue()

    if self.rules_watcher:
        self.rules_watcher.stop()

    # ❌ No timeout - can hang forever!
    if self.ipc_server:
        await self.ipc_server.stop()

    # ❌ No timeout - can hang forever!
    if self.connection:
        self.connection.close()

    logger.info("Daemon shutdown complete")
```

### Problem
Each `await` can block indefinitely if:
- IPC server has stalled connections
- Project switch queue is deadlocked
- i3 IPC socket is unresponsive

When systemd sends SIGTERM, the daemon tries to shutdown, but hangs on these operations. After 90 seconds, systemd gives up and sends SIGKILL.

### Correct Implementation
```python
async def shutdown(self) -> None:
    """Graceful shutdown with timeouts."""
    logger.info("Shutting down daemon...")

    if self.health_monitor:
        self.health_monitor.notify_stopping()

    # ✅ Wrap all shutdown operations in timeout
    try:
        async with asyncio.timeout(10):  # 10 second total timeout
            # Shutdown project switch queue (2s timeout)
            try:
                async with asyncio.timeout(2):
                    await shutdown_project_switch_queue()
            except asyncio.TimeoutError:
                logger.warning("Project switch queue shutdown timed out")

            # Stop file watcher (synchronous, fast)
            if self.rules_watcher:
                self.rules_watcher.stop()

            # Stop IPC server (5s timeout)
            if self.ipc_server:
                try:
                    async with asyncio.timeout(5):
                        await self.ipc_server.stop()
                except asyncio.TimeoutError:
                    logger.warning("IPC server shutdown timed out")

            # Close i3 connection (synchronous, usually fast)
            if self.connection:
                self.connection.close()

    except asyncio.TimeoutError:
        logger.error("Overall shutdown timed out after 10s")

    logger.info("Daemon shutdown complete")
```

---

## Issue #3: Inadequate Systemd Configuration

### Current Configuration
```nix
serviceConfig = {
  Type = "notify";
  WatchdogSec = 30;
  Restart = "always";
  RestartSec = 5;
  # ❌ No TimeoutStopSec specified (using default 90s)
  # ❌ No TimeoutStartSec specified (using default 90s)

  # Resource limits
  MemoryMax = "100M";
  MemoryHigh = "80M";
  CPUQuota = "50%";
  TasksMax = 50;
  # ...
};
```

### Problem
- **90 second stop timeout is too long** - Users notice daemon is unresponsive
- **No explicit configuration** - Relying on systemd defaults is fragile
- **Watchdog interval mismatch** - Daemon sends pings every 15s, systemd expects <30s (close margin)

### Recommended Configuration
```nix
serviceConfig = {
  Type = "notify";

  # ✅ Watchdog: Expect ping every 20s (daemon sends every 10s = 2x safety margin)
  WatchdogSec = 20;

  # ✅ Startup: 30s is plenty for initialization
  TimeoutStartSec = 30;

  # ✅ Shutdown: 15s is enough with proper timeout handling in code
  TimeoutStopSec = 15;

  # ✅ Quick restart on failure
  Restart = "always";
  RestartSec = 2;  # Reduced from 5s to 2s for faster recovery

  # ✅ Limit restart frequency (prevent boot loop)
  StartLimitIntervalSec = 60;
  StartLimitBurst = 5;

  # Resource limits (keep existing)
  MemoryMax = "100M";
  MemoryHigh = "80M";
  CPUQuota = "50%";
  TasksMax = 50;
  # ...
};
```

---

## Issue #4: Unexplained USR1 Signal

### Evidence
```
Nov 04 16:30:51 - Main process exited, code=killed, status=10/USR1
```

### Possible Causes
1. **Manual signal for debugging** - Did you send `kill -USR1 <pid>`?
2. **Watchdog mechanism** - Some watchdog implementations use USR1
3. **Stray signal** - Another process accidentally sent it

### Recommendation
Add USR1 handler for debugging/diagnostics:
```python
def setup_signal_handlers(self) -> None:
    """Setup signal handlers."""

    def shutdown_handler(signum, frame):
        logger.info(f"Received signal {signum}, initiating shutdown...")
        loop = asyncio.get_event_loop()
        loop.call_soon_threadsafe(self.shutdown_event.set)

    def debug_handler(signum, frame):
        """USR1: Print debug information (don't shutdown)."""
        logger.info("=== DEBUG INFO (USR1) ===")
        logger.info(f"PID: {os.getpid()}")
        logger.info(f"Active tasks: {len(asyncio.all_tasks())}")
        # Print stack traces of all tasks
        for task in asyncio.all_tasks():
            logger.info(f"Task: {task.get_name()} - {task.get_coro()}")
        logger.info("======================")

    signal.signal(signal.SIGTERM, shutdown_handler)
    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGUSR1, debug_handler)  # ✅ Handle USR1 gracefully
```

---

## Fix Summary

### 1. Fix Signal Handling (CRITICAL)
**File**: `daemon.py:573-581`

Replace:
```python
self.shutdown_event.set()
```

With:
```python
loop = asyncio.get_event_loop()
loop.call_soon_threadsafe(self.shutdown_event.set)
```

### 2. Add Shutdown Timeouts (CRITICAL)
**File**: `daemon.py:547-571`

Wrap all shutdown operations in `asyncio.timeout()` contexts with appropriate timeouts (2-5s each, 10s total).

### 3. Improve Systemd Configuration (IMPORTANT)
**File**: `/etc/nixos/modules/services/i3-project-daemon.nix:148-188`

Add explicit timeout configuration:
```nix
TimeoutStartSec = 30;
TimeoutStopSec = 15;
WatchdogSec = 20;  # Update from 30
RestartSec = 2;     # Update from 5
StartLimitIntervalSec = 60;
StartLimitBurst = 5;
```

### 4. Adjust Watchdog Interval (IMPORTANT)
**File**: `daemon.py:94-106`

Change watchdog ping interval to 10s (currently 15s):
```python
# Convert microseconds to seconds, ping at 1/3 interval (not 1/2)
self.watchdog_interval = int(watchdog_usec) / 3_000_000
```

This gives 3x safety margin instead of 2x (20s timeout / 10s ping = 2x buffer).

### 5. Add USR1 Handler (OPTIONAL)
For debugging, add a USR1 handler that prints diagnostics without shutting down.

---

## Testing Plan

After applying fixes:

### 1. Test Graceful Shutdown
```bash
# Start daemon
sudo systemctl start i3-project-daemon

# Wait for READY
sleep 2

# Send SIGTERM (should shutdown cleanly in <5s)
sudo systemctl stop i3-project-daemon

# Check logs for clean shutdown
journalctl --system -u i3-project-daemon --since "1 minute ago" | grep -E "shutdown|STOP"
```

**Expected**: No "timed out" or "SIGKILL" messages.

### 2. Test Watchdog
```bash
# Start daemon
sudo systemctl start i3-project-daemon

# Watch watchdog pings (should see one every ~10s)
journalctl --system -u i3-project-daemon -f | grep WATCHDOG
```

**Expected**: Regular "WATCHDOG=1" pings, no watchdog timeout failures.

### 3. Test Restart Resilience
```bash
# Crash daemon 3 times quickly
for i in {1..3}; do
  sudo kill -9 $(pgrep -f i3_project_daemon)
  sleep 1
done

# Check daemon restarted successfully
systemctl --system status i3-project-daemon
```

**Expected**: Daemon auto-restarts, reaches active (running) state.

### 4. Test IPC Responsiveness
```bash
# Query daemon 10 times with 1s interval
for i in {1..10}; do
  timeout 2 i3pm project current || echo "TIMEOUT!"
  sleep 1
done
```

**Expected**: All queries succeed within 2s, no timeouts.

---

## Prevention Strategy

### Code Review Checklist
When modifying daemon code:
- [ ] No blocking I/O operations in main event loop
- [ ] All network/IPC operations have timeouts
- [ ] Signal handlers use `call_soon_threadsafe()` for asyncio operations
- [ ] Shutdown code has per-operation and total timeouts
- [ ] No unbounded loops or recursion

### Monitoring
Add systemd status checks to CI/CD:
```bash
# After deploy, verify daemon health
systemctl --system is-active i3-project-daemon
systemctl --system show i3-project-daemon | grep RestartCount
# RestartCount should be 0 or low (<3)
```

### Logging
Enhance daemon logging to track shutdown sequence:
```python
logger.info("Shutdown step 1/5: Stopping project queue...")
logger.info("Shutdown step 2/5: Stopping rules watcher...")
# etc.
```

This helps identify which operation is hanging during shutdown.

---

## Priority

1. **CRITICAL - Fix signal handling** (30 min)
2. **CRITICAL - Add shutdown timeouts** (45 min)
3. **IMPORTANT - Update systemd config** (15 min)
4. **IMPORTANT - Test all scenarios** (30 min)

**Total estimated time**: 2 hours

---

## References

- [Python asyncio signal handling](https://docs.python.org/3/library/asyncio-eventloop.html#asyncio.loop.call_soon_threadsafe)
- [systemd service configuration](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
- [systemd watchdog](https://www.freedesktop.org/software/systemd/man/sd_watchdog_enabled.html)
