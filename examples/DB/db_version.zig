const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;

fn listUsers(r: zap.Request, ctx: Mesh.Context) void {
    const d = ctx.db.asDdb() orelse
        return response.sendInternalServerError(r, "DB unavailable");
    _ = d;
    response.sendBody(r, "[]");
}

fn createUser(r: zap.Request, ctx: Mesh.Context) void {
    _ = ctx;
    response.sendBody(r, "{\"ok\": true}");
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    // Открываем реальный DDB (сигнатура init — как у VoidDB).
    var real = try Mesh.ddb.DB.init("ExampleDB", alloc, init.io);
    defer real.deinit();

    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "users", .handlers = &.{
                .{ .method = .GET, .handler = listUsers },
                .{ .method = .POST, .handler = createUser },
            } },
        },
    };

    var srv = Mesh.Server{
        .db = .fromDDB(&real), // фоновый save() пишет на диск
        .allocator = alloc,
        .root = &routes,
        .port = 8080,
        .threads = 4,
        .io = init.io,
    };
    try srv.start();
}
