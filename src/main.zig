const std = @import("std");
const Io = std.Io;

const Mesh = @import("root.zig");

const NoteType = struct {
    title: []const u8,
    text: []const u8,
};

const router = Mesh.RouteNode{
    .segment = "",
    .handlers = &.{.{ .method = .GET, .handler = home }},
    .children = &.{
        .{
            .segment = "note",
            .children = &.{
                .{
                    .segment = ":id",
                    .param = "id",
                    .handlers = &.{
                        .{ .method = .GET, .handler = noteById },
                        .{ .method = .DELETE, .handler = deleteNoteById },
                    },
                    .children = &.{},
                },
            },
        },
    },
};

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{ .thread_safe = true }){};
    defer _ = gpa.deinit();
    const gpa_allocator = gpa.allocator();

    const io = init.io;

    var db: *Mesh.ddb.DB = try DBInit(gpa_allocator, io);
    defer {
        db.save() catch |err| std.debug.print("ERROR SAVE: {}\n", .{err});
        DBdeinit(db);
    }

    var arena = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    var server = Mesh.Server{
        .db = .fromDDB(db),
        .allocator = arena_allocator,
        .port = 8000,
        .root = &router,
        .threads = 4,
        .log = true,
        .middlewares = &.{logger},
        .io = io,
    };

    try server.start();
}

fn DBInit(allocator: std.mem.Allocator, io: Io) !*Mesh.ddb.DB {
    const db_ptr: *Mesh.ddb.DB = try allocator.create(Mesh.ddb.DB);
    errdefer allocator.destroy(db_ptr);

    db_ptr.* = try Mesh.ddb.DB.init("MeshTest", allocator, io);
    errdefer db_ptr.deinit();
    try db_ptr.load();

    if (db_ptr.getTable("notes") == null) {
        try db_ptr.createTable("notes", NoteType);
    }

    const NotesTable = db_ptr.getTable("notes") orelse return error.NotFoundTable;

    if (NotesTable.len() == 0) {
        const note1 = NoteType{
            .title = "About mesh",
            .text = "Mesh is a framework for easily creating websites using ZAP and DDB.",
        };

        const note2 = NoteType{
            .title = "Getting started",
            .text = "Install Zig, add mesh as a dependency, and call Mesh.start() in your main function.",
        };

        const note3 = NoteType{
            .title = "Routing basics",
            .text = "Define routes as a tree of RouteNode structs. Each node has a segment, handler, and optional method.",
        };

        const note4 = NoteType{
            .title = "Using DDB",
            .text = "DDB is the built-in database. Create tables with createTable(), then insert and query rows by struct type.",
        };

        const NoteElement1 = try Mesh.ddb.Adapter.toElement(note1, allocator);
        const NoteElement2 = try Mesh.ddb.Adapter.toElement(note2, allocator);
        const NoteElement3 = try Mesh.ddb.Adapter.toElement(note3, allocator);
        const NoteElement4 = try Mesh.ddb.Adapter.toElement(note4, allocator);

        const NotesElements = [_]Mesh.ddb.Element{ NoteElement1, NoteElement2, NoteElement3, NoteElement4 };

        try NotesTable.appendMany(&NotesElements);
    }

    return db_ptr;
}

pub fn DBdeinit(self: *Mesh.ddb.DB) void {
    const alloc = self.allocator;
    self.deinit();
    alloc.destroy(self);
}

fn logger(r: Mesh.zap.Request, ctx: Mesh.Context) bool {
    _ = r;

    if (ctx.db.asDdb()) |_| {
        std.log.debug("ok", .{});
        return true;
    }

    std.log.debug("db not found!", .{});
    return false;
}

fn home(r: Mesh.zap.Request, ctx: Mesh.Context) void {
    _ = ctx;
    Mesh.response.sendBody(r, "Hello, World!");
}

fn noteById(r: Mesh.zap.Request, ctx: Mesh.Context) void {
    const db = ctx.db.asDdb() orelse {
        Mesh.response.sendError(r, .service_unavailable, "DB not enabled");
        return;
    };
    const id = ctx.params[0] orelse {
        Mesh.response.sendBadRequest(r, "missing id");
        return;
    };

    const note_id = std.fmt.parseInt(u32, id, 10) catch {
        Mesh.response.sendBadRequest(r, "id must be a number");
        return;
    };

    const NotesTable = db.getTable("notes") orelse {
        Mesh.response.sendError(r, .internal_server_error, "Not Found Table");
        return;
    };

    if (note_id >= NotesTable.len()) {
        Mesh.response.sendError(r, .not_found, "Not Found Note");
        return;
    }

    const note = NotesTable.get(note_id) orelse {
        Mesh.response.sendError(r, .not_found, "Not Found Note");
        return;
    };

    const title = note.getAs([]const u8, "title") orelse {
        Mesh.response.sendError(r, .internal_server_error, "Invalid get title");
        return;
    };

    const text = note.getAs([]const u8, "text") orelse {
        Mesh.response.sendError(r, .internal_server_error, "Invalid get text");
        return;
    };

    const NoteFinal = NoteType{
        .title = title,
        .text = text,
    };

    r.setHeader("Content-Type", "application/json; charset=utf-8") catch |err| {
        std.debug.print("Failed to set header: {}\n", .{err});
    };

    const json = std.json.Stringify.valueAlloc(ctx.allocator, NoteFinal, .{}) catch {
        Mesh.response.sendError(r, .internal_server_error, "Out of memory");
        return;
    };

    Mesh.response.sendBody(r, json);
}

fn deleteNoteById(r: Mesh.zap.Request, ctx: Mesh.Context) void {
    const db = ctx.db.asDdb() orelse {
        Mesh.response.sendError(r, .service_unavailable, "DB not enabled");
        return;
    };
    const id = ctx.params[0] orelse {
        Mesh.response.sendBadRequest(r, "missing id");
        return;
    };

    const note_id = std.fmt.parseInt(u32, id, 10) catch {
        Mesh.response.sendBadRequest(r, "id must be a number");
        return;
    };

    const NotesTable = db.getTable("notes") orelse {
        Mesh.response.sendError(r, .internal_server_error, "Not Found Table");
        return;
    };

    if (note_id >= NotesTable.len()) {
        Mesh.response.sendError(r, .not_found, "Not Found Note");
        return;
    }

    NotesTable.remove(note_id) catch {
        Mesh.response.sendError(r, .not_found, "Not Found Note");
        return;
    };
}
