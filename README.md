# PC-Server-condition-checking-app
Zig app that checks your Linux or Windows PC/Server condition stats (uptime, available RAM, CPU load) and sends them over SSH to another machine.

## Platforms

The monitored machine can run Linux or Windows; the platform is picked at compile time.

| File | Role |
|------|------|
| `pulse.zig` | Main loop, report formatting, SSH delivery |
| `platform_linux.zig` | Metrics from `/proc/uptime`, `/proc/meminfo`, `/proc/stat` |
| `platform_windows.zig` | Metrics from Win32 (`GetTickCount64`, `GlobalMemoryStatusEx`, `GetSystemTimes`) |

## Build

```
zig build-exe pulse.zig                        # for the host OS
zig build-exe pulse.zig -target x86_64-linux   # cross-compile for Linux
zig build-exe pulse.zig -target x86_64-windows # cross-compile for Windows
zig test platform_windows.zig                  # sanity tests (run on Windows)
```

Set `host` in `pulse.zig` to your SSH target. The report is delivered with `msg *` on the receiving side, so the receiver must be a Windows machine with `msg.exe` (not available in Home editions). The sender needs an `ssh` client in `PATH` (bundled with Windows 10/11 as OpenSSH).
