const std = @import("std");
const Mesh = @import("root.zig");

const zap = Mesh.zap;
const ddb = Mesh.ddb;
const router = @import("router.zig");
const response = @import("response.zig");
const method = @import("method.zig");
const db_mod = @import("db.zig");

/// Middleware signature. Return false to stop chain (response already sent).
pub const Middleware = *const fn (r: zap.Request, ctx: router.Context) bool;

/// HTTP server with routing, middlewares and periodic DB save.
pub const Server = struct {
    // Static state used by zap callbacks (they don't get userdata).
    var ctx: ?router.Context = null;
    var root_route: ?*const router.RouteNode = null;
    var mws: []const Middleware = &.{};
    var running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

    db: db_mod.DB,
    allocator: std.mem.Allocator,
    root: *const router.RouteNode,
    port: u16 = 8080,
    threads: i16 = 4,
    log: bool = true,
    io: std.Io,
    middlewares: []const Middleware = &.{},

    worker_thread: ?std.Thread = null,
    started: bool = false,

    /// Starts listener + background worker. Blocks (zap.start).
    pub fn start(self: *Server) !void {
        if (self.started) return error.AlreadyRunning;

        ctx = router.Context{
            .allocator = self.allocator,
            .db = self.db,
        };
        root_route = self.root;
        mws = self.middlewares;
        running.store(true, .release);
        self.started = true;

        // Worker does periodic db.save(). Spawn failure is non-fatal.
        self.worker_thread = std.Thread.spawn(.{}, worker, .{self.io}) catch |err| blk: {
            std.debug.print("worker spawn failed: {}\n", .{err});
            break :blk null;
        };

        var listener = zap.HttpListener.init(.{
            .port = self.port,
            .on_request = onRequestStatic,
            .log = self.log,
        });
        try listener.listen();

        zap.start(.{ .threads = self.threads, .workers = 1 });
    }

    /// Stops worker, clears static state.
    pub fn stop(self: *Server) void {
        running.store(false, .release);
        if (self.worker_thread) |t| {
            t.join();
            self.worker_thread = null;
        }
        ctx = null;
        root_route = null;
        self.started = false;
    }

    /// Zap request callback. Static because zap has no userdata.
    fn onRequestStatic(r: zap.Request) anyerror!void {
        const base = ctx orelse return error.NoContext;
        const root = root_route orelse return error.NoRoutes;

        const path = r.path orelse
            return response.sendBadRequest(r, "Not path");

        const route = router.findRoute(path, root) orelse
            return response.notFound(r, ctx.?.allocator, path);

        const req_m = r.method orelse {
            response.sendBadRequest(r, "Missing HTTP method");
            return;
        };

        // Pick first handler matching request method.
        var chosen: ?router.Handler = null;
        for (route.handlers) |mh| {
            if (method.matches(req_m, mh.method)) {
                chosen = mh.handler;
                break;
            }
        }

        const handler = chosen orelse {
            response.sendError(r, .method_not_allowed, "Method not allowed");
            return;
        };

        // Per-request context with route params.
        const local = router.Context{
            .allocator = base.allocator,
            .db = base.db,
            .params = route.params,
        };

        // Middlewares: false -> stop, response already sent.
        for (mws) |mw| {
            if (!mw(r, local)) return;
        }

        handler(r, local);
    }

    /// Background worker: every ~5s saves DB while running.
    fn worker(io: std.Io) void {
        while (running.load(.acquire)) {
            var i: usize = 0;
            while (i < 5 and running.load(.acquire)) : (i += 1) {
                io.sleep(.fromSeconds(1), std.Io.Clock.real) catch |err| {
                    std.debug.print("ERROR SLEEP: {}\n", .{err});
                    break;
                };
            }
            if (!running.load(.acquire)) return;

            if (ctx) |c| {
                c.db.save() catch |err| {
                    std.debug.print("ERROR SAVE: {}\n", .{err});
                };
            }
        }
    }
};

// ------------------- Tests -------------------

test "Server defaults" {
    const s = Server{
        .db = undefined,
        .allocator = std.testing.allocator,
        .root = undefined,
        .io = undefined,
    };
    try std.testing.expectEqual(@as(u16, 8080), s.port);
    try std.testing.expectEqual(@as(i16, 4), s.threads);
    try std.testing.expect(s.log);
    try std.testing.expect(!s.started);
    try std.testing.expect(s.worker_thread == null);
    try std.testing.expectEqual(@as(usize, 0), s.middlewares.len);
}

test "static state starts empty" {
    // Can't easily test after start() without a real listener,
    // but we can check initial values before any start.
    try std.testing.expect(Server.ctx == null);
    try std.testing.expect(Server.root_route == null);
    try std.testing.expectEqual(@as(usize, 0), Server.mws.len);
    try std.testing.expect(!Server.running.load(.acquire));
}

test "running flag toggles" {
    Server.running.store(true, .release);
    try std.testing.expect(Server.running.load(.acquire));
    Server.running.store(false, .release);
    try std.testing.expect(!Server.running.load(.acquire));
}

test "stop without start does not crash" {
    var s = Server{
        .db = undefined,
        .allocator = std.testing.allocator,
        .root = undefined,
        .io = undefined,
    };
    s.stop();
    try std.testing.expect(!s.started);
}
