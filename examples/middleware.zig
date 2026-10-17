const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;

var request_count: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

fn logging(r: zap.Request, _: Mesh.Context) bool {
    const n = request_count.fetchAdd(1, .monotonic) + 1;
    std.debug.print("[log] #{d} {s} {s}\n", .{
        n,
        r.method orelse "?",
        r.path orelse "?",
    });
    return true;
}

fn auth(r: zap.Request, _: Mesh.Context) bool {
    const token = r.getHeader("x-token") orelse {
        response.sendError(r, .forbidden, "missing x-token");
        return false;
    };
    if (!std.mem.eql(u8, token, "secret")) {
        response.sendError(r, .forbidden, "bad token");
        return false;
    }
    return true;
}

fn public(r: zap.Request, _: Mesh.Context) void {
    response.sendBody(r, "public ok");
}

fn secret(r: zap.Request, _: Mesh.Context) void {
    response.sendBody(r, "secret ok");
}

fn stats(r: zap.Request, ctx: Mesh.Context) void {
    const n = request_count.load(.monotonic);
    const msg = std.fmt.allocPrint(ctx.allocator, "requests: {d}", .{n}) catch return;
    defer ctx.allocator.free(msg);
    response.sendBody(r, msg);
}

pub fn main(init: std.process.Init) !void {
    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "public", .handlers = &.{.{ .method = .GET, .handler = public }} },
            .{ .segment = "secret", .handlers = &.{.{ .method = .GET, .handler = secret }} },
            .{ .segment = "stats", .handlers = &.{.{ .method = .GET, .handler = stats }} },
        },
    };

    var srv = Mesh.Server{
        .db = .empty(),
        .allocator = init.gpa,
        .root = &routes,
        .port = 8080,
        .threads = 4,
        .io = init.io,
        .middlewares = &.{ logging, auth },
    };
    try srv.start();
}
