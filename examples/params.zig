const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;

fn getPost(r: zap.Request, ctx: Mesh.Context) void {
    const uid = ctx.params[0] orelse
        return response.sendBadRequest(r, "missing :uid");
    const pid = ctx.params[1] orelse
        return response.sendBadRequest(r, "missing :pid");

    const uid_num = std.fmt.parseInt(u64, uid, 10) catch
        return response.sendBadRequest(r, "uid must be a number");
    const pid_num = std.fmt.parseInt(u64, pid, 10) catch
        return response.sendBadRequest(r, "pid must be a number");

    const msg = std.fmt.allocPrint(
        ctx.allocator,
        "user {d}, post {d}",
        .{ uid_num, pid_num },
    ) catch return;
    defer ctx.allocator.free(msg);

    response.sendBody(r, msg);
}

fn search(r: zap.Request, ctx: Mesh.Context) void {
    const q = response.getParamStrSave(r, ctx.allocator, "q") orelse return;
    defer ctx.allocator.free(q);

    const msg = std.fmt.allocPrint(ctx.allocator, "query: {s}", .{q}) catch return;
    defer ctx.allocator.free(msg);
    response.sendBody(r, msg);
}

pub fn main(init: std.process.Init) !void {
    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "search", .handlers = &.{.{ .method = .GET, .handler = search }} },
            .{ .segment = "users", .children = &.{
                .{ .segment = ":uid", .param = "uid", .children = &.{
                    .{ .segment = "posts", .children = &.{
                        .{ .segment = ":pid", .param = "pid", .handlers = &.{
                            .{ .method = .GET, .handler = getPost },
                        } },
                    } },
                } },
            } },
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
