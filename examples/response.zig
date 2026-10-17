const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;

fn ok(r: zap.Request, _: Mesh.Context) void {
    response.sendBody(r, "hello");
}

fn bad(r: zap.Request, _: Mesh.Context) void {
    response.sendBadRequest(r, "malformed input");
}

fn boom(r: zap.Request, _: Mesh.Context) void {
    response.sendInternalServerError(r, "something broke");
}

fn forbidden(r: zap.Request, _: Mesh.Context) void {
    response.sendError(r, .forbidden, "no access");
}

fn fmtErr(r: zap.Request, ctx: Mesh.Context) void {
    response.sendErrorPrint(
        r,
        .bad_request,
        ctx.allocator,
        "field '{s}' has value {d}, expected < 100",
        .{ "age", 250 },
    );
}

fn param(r: zap.Request, ctx: Mesh.Context) void {
    const name = response.getParamStrSave(r, ctx.allocator, "name") orelse return;
    defer ctx.allocator.free(name);

    const msg = std.fmt.allocPrint(ctx.allocator, "hi, {s}", .{name}) catch return;
    defer ctx.allocator.free(msg);
    response.sendBody(r, msg);
}

fn nf(r: zap.Request, ctx: Mesh.Context) void {
    response.notFound(r, ctx.allocator, "/made/up/path");
}

pub fn main(init: std.process.Init) !void {
    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "ok", .handlers = &.{.{ .method = .GET, .handler = ok }} },
            .{ .segment = "bad", .handlers = &.{.{ .method = .GET, .handler = bad }} },
            .{ .segment = "boom", .handlers = &.{.{ .method = .GET, .handler = boom }} },
            .{ .segment = "forbidden", .handlers = &.{.{ .method = .GET, .handler = forbidden }} },
            .{ .segment = "fmt", .handlers = &.{.{ .method = .GET, .handler = fmtErr }} },
            .{ .segment = "param", .handlers = &.{.{ .method = .GET, .handler = param }} },
            .{ .segment = "nf", .handlers = &.{.{ .method = .GET, .handler = nf }} },
        },
    };

    var srv = Mesh.Server{
        .db = .empty(),
        .allocator = init.gpa,
        .root = &routes,
        .port = 8080,
        .threads = 4,
        .io = init.io,
    };
    try srv.start();
}
