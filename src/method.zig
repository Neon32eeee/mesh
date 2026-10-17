const std = @import("std");
const Mesh = @import("root.zig");

const response = Mesh.response;
const zap = Mesh.zap;

/// HTTP methods we support.
pub const Method = enum { GET, POST, PUT, PATCH, DELETE };

/// Compares request method with name. Returns null if method is not set.
fn eqMethod(r: zap.Request, name: []const u8) ?bool {
    const m = r.method orelse return null;
    return std.mem.eql(u8, m, name);
}

pub fn isGET(r: zap.Request) ?bool {
    return eqMethod(r, "GET");
}
pub fn isPOST(r: zap.Request) ?bool {
    return eqMethod(r, "POST");
}
pub fn isPUT(r: zap.Request) ?bool {
    return eqMethod(r, "PUT");
}
pub fn isPATCH(r: zap.Request) ?bool {
    return eqMethod(r, "PATCH");
}
pub fn isDELETE(r: zap.Request) ?bool {
    return eqMethod(r, "DELETE");
}

/// Checks if raw method string matches expected Method.
/// GET also matches HEAD.
pub fn matches(req: []const u8, m: Method) bool {
    return switch (m) {
        .GET => std.mem.eql(u8, req, "GET") or std.mem.eql(u8, req, "HEAD"),
        .POST => std.mem.eql(u8, req, "POST"),
        .PUT => std.mem.eql(u8, req, "PUT"),
        .PATCH => std.mem.eql(u8, req, "PATCH"),
        .DELETE => std.mem.eql(u8, req, "DELETE"),
    };
}

/// Checks request method against allowed list.
/// Empty list -> allow all. Missing method -> 400. No match -> 405.
/// Returns {} on success, null on failure (error already sent).
pub fn MethodCheck(r: zap.Request, allowed: []const Method) ?void {
    if (allowed.len == 0) return {};

    const m = r.method orelse {
        response.sendError(r, .bad_request, "Missing HTTP method");
        return null;
    };

    for (allowed) |expected| {
        if (matches(m, expected)) return {};
    }

    response.sendError(r, .method_not_allowed, "Invalid method");
    return null;
}

// ------------------- Tests -------------------

test "matches GET and HEAD" {
    try std.testing.expect(matches("GET", .GET));
    try std.testing.expect(matches("HEAD", .GET));
    try std.testing.expect(!matches("POST", .GET));
    try std.testing.expect(!matches("", .GET));
}

test "matches POST/PUT/PATCH/DELETE" {
    try std.testing.expect(matches("POST", .POST));
    try std.testing.expect(matches("PUT", .PUT));
    try std.testing.expect(matches("PATCH", .PATCH));
    try std.testing.expect(matches("DELETE", .DELETE));

    // Cross checks
    try std.testing.expect(!matches("GET", .POST));
    try std.testing.expect(!matches("HEAD", .DELETE));
    try std.testing.expect(!matches("POST", .PUT));
}

test "matches is case sensitive" {
    try std.testing.expect(!matches("get", .GET));
    try std.testing.expect(!matches("Post", .POST));
}

test "matches does not accept empty string for any method" {
    inline for (.{ Method.GET, Method.POST, Method.PUT, Method.PATCH, Method.DELETE }) |m| {
        try std.testing.expect(!matches("", m));
    }
}
