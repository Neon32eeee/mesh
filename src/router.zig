const std = @import("std");
const Mesh = @import("root.zig");

const ddb = Mesh.ddb;
const zap = Mesh.zap;

const method = @import("method.zig");
const response = @import("response.zig");
const db_mod = @import("db.zig");

/// Context for handlers. Up to 4 route params.
pub const Context = struct {
    allocator: std.mem.Allocator,
    db: db_mod.DB,
    params: [4]?[]const u8 = @splat(null),
};

pub const Handler = *const fn (zap.Request, Context) void;

pub const MethodHandler = struct {
    method: method.Method,
    handler: Handler,
};

pub const RouteNode = struct {
    /// Segment name. For the root "/" — an empty string "".
    segment: []const u8,
    /// If null, the segment is exact. If not null, it is the name of a parameter.
    param: ?[]const u8 = null,
    handlers: []const MethodHandler = &.{},
    /// Children. An empty list is a leaf.
    children: []const RouteNode = &.{},
};

/// Result of findRoute: handlers + captured params.
pub const Found = struct {
    handlers: []const MethodHandler,
    params: [4]?[]const u8 = @splat(null),
};

/// Walk the path segments, prefer exact over param, return leaf or null.
pub fn findRoute(path: []const u8, routes: *const RouteNode) ?Found {
    var current: *const RouteNode = routes;
    var params: [4]?[]const u8 = @splat(null);
    var pi: usize = 0;

    var segs = std.mem.tokenizeScalar(u8, path, '/');
    while (segs.next()) |seg| {
        var next: ?*const RouteNode = null;

        // 1) Prefer exact match.
        for (current.children) |*child| {
            if (child.param == null and std.mem.eql(u8, child.segment, seg)) {
                next = child;
                break;
            }
        }

        // 2) Fall back to a dynamic segment.
        if (next == null) {
            const has_more = segs.peek() != null;
            for (current.children) |*child| {
                if (child.param != null) {
                    if (has_more and child.children.len == 0) continue;
                    if (pi < params.len) {
                        params[pi] = seg;
                        pi += 1;
                    }
                    next = child;
                    break;
                }
            }
        }
        current = next orelse return null;
    }

    const list = current.handlers;
    if (list.len == 0) return null;
    return .{ .handlers = list, .params = params };
}

// ------------------- Tests -------------------

/// Stub handler, does nothing.
fn dummy(_: zap.Request, _: Context) void {}

/// Shared test tree:
///   /health              GET
///   /users/me            GET
///   /users/:id           GET, DELETE
///   /users/:uid/posts/:pid  GET
const test_routes = RouteNode{
    .segment = "",
    .children = &.{
        .{
            .segment = "health",
            .handlers = &.{
                .{ .method = .GET, .handler = dummy },
            },
        },
        .{
            .segment = "users",
            .children = &.{
                .{
                    .segment = "me",
                    .handlers = &.{
                        .{ .method = .GET, .handler = dummy },
                    },
                },
                .{
                    .segment = ":id",
                    .param = "id",
                    .handlers = &.{
                        .{ .method = .GET, .handler = dummy },
                        .{ .method = .DELETE, .handler = dummy },
                    },
                },
                .{
                    .segment = ":uid",
                    .param = "uid",
                    .children = &.{
                        .{
                            .segment = "posts",
                            .children = &.{
                                .{
                                    .segment = ":pid",
                                    .param = "pid",
                                    .handlers = &.{
                                        .{ .method = .GET, .handler = dummy },
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
};

test "findRoute exact leaf" {
    const f = findRoute("/health", &test_routes).?;
    try std.testing.expectEqual(@as(usize, 1), f.handlers.len);
    try std.testing.expectEqual(method.Method.GET, f.handlers[0].method);
    for (f.params) |p| try std.testing.expect(p == null);
}

test "findRoute not found" {
    try std.testing.expect(findRoute("/missing", &test_routes) == null);
    try std.testing.expect(findRoute("/health/extra", &test_routes) == null);
    try std.testing.expect(findRoute("/users/me/x", &test_routes) == null);
}

test "findRoute root has no handlers" {
    try std.testing.expect(findRoute("/", &test_routes) == null);
    try std.testing.expect(findRoute("", &test_routes) == null);
}

test "findRoute prefers exact over param" {
    const f = findRoute("/users/me", &test_routes).?;
    // "me" wins over ":id" — no params captured.
    try std.testing.expectEqual(@as(usize, 1), f.handlers.len);
    try std.testing.expect(f.params[0] == null);
}

test "findRoute captures one param" {
    const f = findRoute("/users/42", &test_routes).?;
    try std.testing.expectEqual(@as(usize, 2), f.handlers.len);
    try std.testing.expectEqualStrings("42", f.params[0].?);
    try std.testing.expect(f.params[1] == null);
}

test "findRoute captures two params" {
    const f = findRoute("/users/7/posts/99", &test_routes).?;
    try std.testing.expectEqualStrings("7", f.params[0].?);
    try std.testing.expectEqualStrings("99", f.params[1].?);
    try std.testing.expect(f.params[2] == null);
    try std.testing.expect(f.params[3] == null);
}

test "findRoute ignores empty segments" {
    // tokenizeScalar skips "//", "/./" would not be skipped.
    const f = findRoute("//users//42", &test_routes).?;
    try std.testing.expectEqualStrings("42", f.params[0].?);
}

test "findRoute no trailing slash required" {
    const a = findRoute("/health", &test_routes).?;
    const b = findRoute("/health/", &test_routes).?;
    try std.testing.expectEqual(@as(usize, 1), a.handlers.len);
    try std.testing.expectEqual(@as(usize, 1), b.handlers.len);
}

test "findRoute returns all methods of a node" {
    const f = findRoute("/users/1", &test_routes).?;
    try std.testing.expectEqual(@as(usize, 2), f.handlers.len);
    try std.testing.expectEqual(method.Method.GET, f.handlers[0].method);
    try std.testing.expectEqual(method.Method.DELETE, f.handlers[1].method);
}

test "findRoute empty routes returns null" {
    const empty = RouteNode{ .segment = "" };
    try std.testing.expect(findRoute("/anything", &empty) == null);
    try std.testing.expect(findRoute("/", &empty) == null);
}

test "Found default params are null" {
    const f = Found{ .handlers = &.{} };
    for (f.params) |p| try std.testing.expect(p == null);
}

test "Context default params are null" {
    const c = Context{
        .allocator = std.testing.allocator,
        .db = undefined,
    };
    for (c.params) |p| try std.testing.expect(p == null);
}
