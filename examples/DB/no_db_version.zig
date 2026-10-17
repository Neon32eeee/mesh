const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;

fn hello(r: zap.Request, _: Mesh.Context) void {
    response.sendBody(r, "Hello, world!");
}

fn getUser(r: zap.Request, ctx: Mesh.Context) void {
    const id = ctx.params[0] orelse
        return response.sendBadRequest(r, "No id");

    const msg = std.fmt.allocPrint(ctx.allocator, "user: {s}", .{id}) catch return;
    defer ctx.allocator.free(msg);
    response.sendBody(r, msg);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "hello", .handlers = &.{.{ .method = .GET, .handler = hello }} },
            .{ .segment = "users", .children = &.{
                .{ .segment = ":id", .param = "id", .handlers = &.{.{ .method = .GET, .handler = getUser }} },
            } },
        },
    };

    var srv = Mesh.Server{
        .db = .empty(),
        .allocator = alloc,
        .root = &routes,
        .port = 8080,
        .threads = 4,
        .io = init.io,
    };
    try srv.start(); // блокирует поток
}
