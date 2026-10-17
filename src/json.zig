const std = @import("std");
const Mesh = @import("root.zig");

const response = Mesh.response;
const zap = Mesh.zap;

/// Parses the json document from `Request body` and returns the result.
/// It is recommended to use a `std.heap.ArenaAllocator` or similar.
pub fn parseFromBody(
    comptime T: type,
    allocator: std.mem.Allocator,
    r: zap.Request,
) ?T {
    const body = r.body orelse {
        response.sendBadRequest(r, "Missing JSON body");
        return null;
    };

    return parseFromSlice(T, allocator, body) catch {
        response.sendError(r, .internal_server_error, "Invalid parse JSON");
        return null;
    };
}

/// Parses the json document from `s` and returns the result.
/// It is recommended to use a `std.heap.ArenaAllocator` or similar.
pub fn parseFromSlice(
    comptime T: type,
    allocator: std.mem.Allocator,
    s: []const u8,
) !T {
    const parsed = try std.json.parseFromSlice(T, allocator, s, .{});
    return parsed.value;
}

/// Serializes the value to a JSON string.
/// The caller owns the result and must free it via `allocator.free`.
pub fn stringifyAlloc(
    allocator: std.mem.Allocator,
    value: anytype,
    options: std.json.Stringify.Options,
) ![]u8 {
    return try std.json.Stringify.valueAlloc(allocator, value, options);
}

/// Sends the value as a JSON response with the specified status.
/// It is recommended to use a `std.heap.ArenaAllocator` or similar.
pub fn send(
    allocator: std.mem.Allocator,
    r: zap.Request,
    value: anytype,
) !void {
    const json = try stringifyAlloc(allocator, value, .{});
    defer allocator.free(json);
    response.sendBody(r, json);
}

// ------------------- Tests -------------------

const User = struct {
    id: u32,
    name: []const u8,
};

test "parseFromSlice parses simple struct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const json =
        \\{"id": 42, "name": "alice"}
    ;

    const user = try parseFromSlice(User, arena.allocator(), json);
    try std.testing.expectEqual(@as(u32, 42), user.id);
    try std.testing.expectEqualStrings("alice", user.name);
}

test "parseFromSlice parses numbers and arrays" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const json = "[1, 2, 3, 4]";
    const arr = try parseFromSlice([4]i32, arena.allocator(), json);
    try std.testing.expectEqualSlices(i32, &.{ 1, 2, 3, 4 }, &arr);
}

test "parseFromSlice parses optional and nested" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const Payload = struct {
        ok: bool,
        msg: ?[]const u8,
    };

    const p1 = try parseFromSlice(Payload, arena.allocator(), "{\"ok\": true, \"msg\": null}");
    try std.testing.expect(p1.ok);
    try std.testing.expect(p1.msg == null);

    const p2 = try parseFromSlice(Payload, arena.allocator(), "{\"ok\": false, \"msg\": \"nope\"}");
    try std.testing.expect(!p2.ok);
    try std.testing.expectEqualStrings("nope", p2.msg.?);
}

test "parseFromSlice fails on invalid json" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    try std.testing.expectError(
        error.SyntaxError,
        parseFromSlice(User, arena.allocator(), "{not json"),
    );
}

test "parseFromSlice fails on wrong shape" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    // `id` should be a number, not a string.
    try std.testing.expectError(
        error.InvalidCharacter,
        parseFromSlice(User, arena.allocator(), "{\"id\": \"x\", \"name\": \"a\"}"),
    );
}

test "stringifyAlloc serializes simple struct" {
    const allocator = std.testing.allocator;

    const user = User{ .id = 42, .name = "alice" };
    const json = try stringifyAlloc(allocator, user, .{});
    defer allocator.free(json);

    try std.testing.expectEqualStrings("{\"id\":42,\"name\":\"alice\"}", json);
}

test "stringifyAlloc serializes numbers and arrays" {
    const allocator = std.testing.allocator;

    const arr = [_]i32{ 1, 2, 3, 4 };
    const json = try stringifyAlloc(allocator, arr, .{});
    defer allocator.free(json);

    try std.testing.expectEqualStrings("[1,2,3,4]", json);
}

test "stringifyAlloc serializes optional null" {
    const allocator = std.testing.allocator;

    const Payload = struct {
        ok: bool,
        msg: ?[]const u8,
    };

    const p = Payload{ .ok = true, .msg = null };
    const json = try stringifyAlloc(allocator, p, .{});
    defer allocator.free(json);

    try std.testing.expectEqualStrings("{\"ok\":true,\"msg\":null}", json);
}

test "stringifyAlloc serializes optional value" {
    const allocator = std.testing.allocator;

    const Payload = struct {
        ok: bool,
        msg: ?[]const u8,
    };

    const p = Payload{ .ok = false, .msg = "nope" };
    const json = try stringifyAlloc(allocator, p, .{});
    defer allocator.free(json);

    try std.testing.expectEqualStrings("{\"ok\":false,\"msg\":\"nope\"}", json);
}

test "stringifyAlloc round-trips through parseFromSlice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const original = User{ .id = 7, .name = "bob" };

    const json = try stringifyAlloc(arena.allocator(), original, .{});
    const parsed = try parseFromSlice(User, arena.allocator(), json);

    try std.testing.expectEqual(original.id, parsed.id);
    try std.testing.expectEqualStrings(original.name, parsed.name);
}

test "stringifyAlloc with whitespace option" {
    const allocator = std.testing.allocator;

    const user = User{ .id = 1, .name = "x" };
    const json = try stringifyAlloc(allocator, user, .{ .whitespace = .indent_2 });
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "  ") != null);
}

test "stringifyAlloc propagates error from jsonStringify" {
    const allocator = std.testing.allocator;

    const Bad = struct {
        pub fn jsonStringify(_: @This(), _: anytype) error{WriteFailed}!void {
            return error.WriteFailed;
        }
    };

    try std.testing.expectError(
        error.OutOfMemory,
        stringifyAlloc(allocator, Bad{}, .{}),
    );
}
