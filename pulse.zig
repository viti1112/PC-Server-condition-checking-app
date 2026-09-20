const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .linux => @import("platform_linux.zig"),
    .windows => @import("platform_windows.zig"),
    else => @compileError("unsupported OS: only Linux and Windows are supported"),
};

const host = ""; // your ssh host here
const interval_seconds = 30;

const Report = struct {
    uptime_seconds: f64,
    mem_available_kb: u64,
};

fn cpuPercent(prev: platform.CpuTicks, curr: platform.CpuTicks) f64 {
    const total_delta: f64 = @floatFromInt(curr.total - prev.total);
    const idle_delta: f64 = @floatFromInt(curr.idle - prev.idle);
    if (total_delta == 0) return 0;
    return (1.0 - idle_delta / total_delta) * 100.0;
}

fn collectReport(io: std.Io, allocator: std.mem.Allocator) !Report {
    return Report{
        .uptime_seconds = try platform.readUptime(io, allocator),
        .mem_available_kb = try platform.readMemAvailableKb(io, allocator),
    };
}

fn formatReport(allocator: std.mem.Allocator, report: Report, cpu_percent: f64) ![]u8 {
    const uptime_minutes = report.uptime_seconds / 60.0;
    const mem_kb_f: f64 = @floatFromInt(report.mem_available_kb);
    const mem_available_mb = mem_kb_f / 1024.0;

    return std.fmt.allocPrint(
        allocator,
        "uptime: {d:.1} min, mem available: {d:.1} MB, cpu: {d:.1}%",
        .{ uptime_minutes, mem_available_mb, cpu_percent },
    );
}

fn sendReport(
    io: std.Io,
    allocator: std.mem.Allocator,
    text: []const u8,
    target_host: []const u8,
) !void {
    const command = try std.fmt.allocPrint(allocator, "msg * \"{s}\"", .{text});
    defer allocator.free(command);

    var child = try std.process.spawn(io, .{
        .argv = &.{ "ssh", target_host, command },
    });

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.SshFailed,
        else => return error.SshFailed,
    }
}

fn sendWithRetry(
    io: std.Io,
    allocator: std.mem.Allocator,
    text: []const u8,
    target_host: []const u8,
    attempts: u8,
) void {
    var i: u8 = 0;
    while (i < attempts) : (i += 1) {
        sendReport(io, allocator, text, target_host) catch |err| {
            std.debug.print("attempt {d} failed: {}\n", .{ i + 1, err });
            io.sleep(.fromNanoseconds(5 * std.time.ns_per_s), .awake) catch |sleep_err| {
                std.debug.print("could not wait between retry attempts: {}\n", .{sleep_err});
                return;
            };
            continue;
        };
        std.debug.print("report sent to {s}\n", .{target_host});
        return;
    }
    std.debug.print("sending failed after {d} attempts\n", .{attempts});
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prev_ticks = try platform.readCpuTicks(io, allocator);

    while (true) {
        // Sleep first so the CPU delta spans a full interval and a failing
        // iteration (`continue`) cannot spin the loop.
        try io.sleep(.fromNanoseconds(interval_seconds * std.time.ns_per_s), .awake);

        const curr_ticks = platform.readCpuTicks(io, allocator) catch |err| {
            std.debug.print("failed to read cpu stats: {}\n", .{err});
            continue;
        };
        const cpu_percent = cpuPercent(prev_ticks, curr_ticks);
        prev_ticks = curr_ticks;

        const report = collectReport(io, allocator) catch |err| {
            std.debug.print("failed to collect metrics: {}\n", .{err});
            continue;
        };

        const text = formatReport(allocator, report, cpu_percent) catch |err| {
            std.debug.print("failed to build the report: {}\n", .{err});
            continue;
        };
        defer allocator.free(text);

        sendWithRetry(io, allocator, text, host, 3);
    }
}
