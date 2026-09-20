const std = @import("std");

pub const CpuTicks = struct {
    idle: u64,
    total: u64,
};

const FILETIME = extern struct {
    low: u32,
    high: u32,

    fn toU64(self: FILETIME) u64 {
        return (@as(u64, self.high) << 32) | self.low;
    }
};

const MEMORYSTATUSEX = extern struct {
    length: u32,
    memory_load: u32,
    total_phys: u64,
    avail_phys: u64,
    total_page_file: u64,
    avail_page_file: u64,
    total_virtual: u64,
    avail_virtual: u64,
    avail_extended_virtual: u64,
};

extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
extern "kernel32" fn GetSystemTimes(idle: *FILETIME, kernel: *FILETIME, user: *FILETIME) callconv(.winapi) i32;
extern "kernel32" fn GlobalMemoryStatusEx(status: *MEMORYSTATUSEX) callconv(.winapi) i32;

// The signatures mirror platform_linux.zig so pulse.zig can use either one;
// the Win32 calls below need neither `io` nor an allocator.

pub fn readUptime(io: std.Io, allocator: std.mem.Allocator) !f64 {
    _ = io;
    _ = allocator;
    const millis: f64 = @floatFromInt(GetTickCount64());
    return millis / 1000.0;
}

pub fn readMemAvailableKb(io: std.Io, allocator: std.mem.Allocator) !u64 {
    _ = io;
    _ = allocator;
    var status = std.mem.zeroes(MEMORYSTATUSEX);
    status.length = @sizeOf(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&status) == 0) return error.SystemCallFailed;
    return status.avail_phys / 1024;
}

pub fn readCpuTicks(io: std.Io, allocator: std.mem.Allocator) !CpuTicks {
    _ = io;
    _ = allocator;
    var idle: FILETIME = undefined;
    var kernel: FILETIME = undefined;
    var user: FILETIME = undefined;
    if (GetSystemTimes(&idle, &kernel, &user) == 0) return error.SystemCallFailed;

    // Kernel time already includes idle time, so total = kernel + user.
    return CpuTicks{
        .idle = idle.toU64(),
        .total = kernel.toU64() + user.toU64(),
    };
}

test "uptime is positive" {
    const io = std.testing.io;
    try std.testing.expect(try readUptime(io, std.testing.allocator) > 0);
}

test "available memory is positive and below physical total" {
    const io = std.testing.io;
    const avail_kb = try readMemAvailableKb(io, std.testing.allocator);
    try std.testing.expect(avail_kb > 0);
}

test "cpu ticks are monotonic and idle never exceeds total" {
    const io = std.testing.io;
    const first = try readCpuTicks(io, std.testing.allocator);
    const second = try readCpuTicks(io, std.testing.allocator);
    try std.testing.expect(first.idle <= first.total);
    try std.testing.expect(second.total >= first.total);
    try std.testing.expect(second.idle >= first.idle);
}
