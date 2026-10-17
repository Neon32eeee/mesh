const std = @import("std");
const Mesh = @import("root.zig");

const zap = Mesh.zap;

const Allocator = std.mem.Allocator;

// Compares strings, just a shortcut for the regular std.mem.eql
fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Helper function for sending errors (simplifies the code)
pub fn sendError(r: zap.Request, status: zap.http.StatusCode, msg: []const u8) void {
    r.setStatus(status);
    r.sendBody(msg) catch |err| {
        std.debug.print("sendBody failed: {}\n", .{err});
    };
}

/// Sends 400 Bad Request.
pub fn sendBadRequest(r: zap.Request, msg: []const u8) void {
    sendError(r, .bad_request, msg);
}

/// Sends 500 Internal Server Error.
pub fn sendInternalServerError(r: zap.Request, msg: []const u8) void {
    sendError(r, .internal_server_error, msg);
}

/// Helper function for sending errors with printing the error message from the comptime string and arguments
pub fn sendErrorPrint(r: zap.Request, status: zap.http.StatusCode, allocator: Allocator, comptime fmt: []const u8, args: anytype) void {
    r.setStatus(status);

    const msg = std.fmt.allocPrint(allocator, fmt, args) catch {
        sendError(r, .internal_server_error, "Out of memory");
        return;
    };
    defer allocator.free(msg);

    r.sendBody(msg) catch |err| {
        std.debug.print("sendBody failed: {}\n", .{err});
    };
}

/// Sends 200 OK with body.
pub fn sendBody(r: zap.Request, msg: []const u8) void {
    r.setStatus(.ok);
    r.sendBody(msg) catch |err| {
        std.debug.print("sendBody failed: {}\n", .{err});
    };
}

/// Gets param or sends error and returns null.
pub fn getParamStrSave(r: zap.Request, allocator: Allocator, name: []const u8) ?[]const u8 {
    return r.getParamStr(allocator, name) catch {
        sendErrorPrint(r, .bad_request, allocator, "Invalid parse {s}", .{name});
        return null;
    } orelse {
        sendErrorPrint(r, .bad_request, allocator, "Missing {s}", .{name});
        return null;
    };
}

/// Sends 404 with path.
pub fn notFound(r: zap.Request, allocator: std.mem.Allocator, path: []const u8) void {
    sendErrorPrint(
        r,
        .not_found,
        allocator,
        "404 - Not Found: {s}",
        .{path},
    );
}

// ------------------- Tests -------------------

test "eql works" {
    try std.testing.expect(eql("hello", "hello"));
    try std.testing.expect(!eql("hello", "world"));
    try std.testing.expect(!eql("hello", "hell"));
    try std.testing.expect(!eql("", "a"));
    try std.testing.expect(eql("", ""));
}
