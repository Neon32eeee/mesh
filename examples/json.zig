const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const response = Mesh.response;
const json = Mesh.json;

const CreateUser = struct {
    name: []const u8,
    age: u32,
    email: ?[]const u8 = null,
};

const UserOut = struct {
    id: u32,
    name: []const u8,
    email: ?[]const u8 = null,
};

/// POST /users — принимаем JSON, отвечаем JSON.
fn createUser(r: zap.Request, ctx: Mesh.Context) void {
    var arena = std.heap.ArenaAllocator.init(ctx.allocator);
    defer arena.deinit();

    // parseFromBody сам отправит 400/500 и вернёт null при ошибке.
    const payload = json.parseFromBody(CreateUser, arena.allocator(), r) orelse return;

    // Формируем ответ.
    const out = UserOut{
        .id = 42, // тут была бы запись в БД
        .name = payload.name,
        .email = payload.email,
    };

    // json.send отправит 200 + сериализованный JSON.
    json.send(ctx.allocator, r, out) catch |err| {
        response.sendInternalServerError(r, @errorName(err));
    };
}

/// GET /echo — сериализуем и парсим из строки, отвечаем текстом.
fn echo(r: zap.Request, ctx: Mesh.Context) void {
    const seed = UserOut{ .id = 7, .name = "bob", .email = null };

    // stringifyAlloc — ручная сериализация (когда нужно что-то сделать со строкой).
    const s = json.stringifyAlloc(ctx.allocator, seed, .{}) catch
        return response.sendInternalServerError(r, "oom");
    defer ctx.allocator.free(s);

    // parseFromSlice — обратный разбор.
    const parsed = json.parseFromSlice(UserOut, ctx.allocator, s) catch
        return response.sendInternalServerError(r, "bad json");

    const msg = std.fmt.allocPrint(
        ctx.allocator,
        "round-trip: id={d} name={s}",
        .{ parsed.id, parsed.name },
    ) catch return response.sendInternalServerError(r, "oom");
    defer ctx.allocator.free(msg);

    response.sendBody(r, msg);
}

/// GET /pretty — тот же JSON, но с отступами.
fn pretty(r: zap.Request, ctx: Mesh.Context) void {
    const out = UserOut{ .id = 1, .name = "x", .email = "x@y.z" };
    const s = json.stringifyAlloc(ctx.allocator, out, .{ .whitespace = .indent_2 }) catch
        return response.sendInternalServerError(r, "oom");
    defer ctx.allocator.free(s);

    response.sendBody(r, s);
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(init.gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const routes = Mesh.RouteNode{
        .segment = "",
        .children = &.{
            .{ .segment = "users", .handlers = &.{.{ .method = .POST, .handler = createUser }} },
            .{ .segment = "echo", .handlers = &.{.{ .method = .GET, .handler = echo }} },
            .{ .segment = "pretty", .handlers = &.{.{ .method = .GET, .handler = pretty }} },
        },
    };

    var srv = Mesh.Server{
        .db = .empty(),
        .allocator = a,
        .root = &routes,
        .port = 8080,
        .threads = 4,
        .io = init.io,
    };
    try srv.start();
}
