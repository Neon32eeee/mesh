# Mesh

## About

Mesh is a lightweight HTTP server library for Zig, built on top of [zap](https://github.com/zigzap/zap), with a tree-based router, middleware support, JSON helpers, and optional periodic database saving via [DDB](https://github.com/Neon32eeee/DDB.zig).

Requirements:
- Zig version: `0.16.0`
- OS:
  - Linux
  - macOS

## Features

- **Tree-based router** - exact and dynamic (`:param`) segments, exact matches preferred.
- **Method handlers** - multiple HTTP methods per route node.
- **Middlewares** - a simple chain with early exit.
- **Context** - per-request allocator, DB handle, and up to 4 captured route params.
- **DB abstraction** - `DB` can wrap a real DDB, a no-op VoidDB, or nothing at all.
- **JSON helpers** - parse request bodies or slices into Zig types.
- **Response helpers** - quick error, not-found, and body senders.
- **Background saver** - optional worker thread that periodically calls `db.save()`.

## Example

```zig
const std = @import("std");
const Mesh = @import("Mesh");

const zap = Mesh.zap;
const router = @import("router.zig");
const response = @import("response.zig");

fn hello(r: zap.Request, ctx: router.Context) void {
    response.sendBody(r, "Hello from Mesh!");
}

const routes = router.RouteNode{
    .segment = "",
    .children = &.{
        .{
            .segment = "hello",
            .handlers = &.{
                .{ .method = .GET, .handler = hello },
            },
        },
    },
};

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var server = Mesh.Server{
        .db = .empty(),
        .allocator = gpa.allocator(),
        .root = &routes,
        .port = 8080,
        .io = init.io,
    };
    defer server.stop();

    try server.start();
}
```

## Router

`RouteNode` describes your tree. An empty `segment` is the root. A node with `param = "name"` matches any segment and captures it.

```zig
const routes = router.RouteNode{
    .segment = "",
    .children = &.{
        .{
            .segment = "users",
            .children = &.{
                .{
                    .segment = "me",
                    .handlers = &.{ .{ .method = .GET, .handler = getMe } },
                },
                .{
                    .segment = ":id",
                    .param = "id",
                    .handlers = &.{
                        .{ .method = .GET,    .handler = getUser },
                        .{ .method = .DELETE, .handler = delUser },
                    },
                },
            },
        },
    },
};
```

Lookup is done with `router.findRoute(path, &routes)`, returning a `Found` with handlers and captured params. Exact children take priority over dynamic ones.

## Middleware

A middleware is a function `fn (r: zap.Request, ctx: router.Context) bool`. Returning `false` stops the chain - assume the response has already been sent.

```zig
fn auth(r: zap.Request, ctx: router.Context) bool {
    if (r.getHeader("X-Token") == null) {
        response.sendError(r, .unauthorized, "Missing token");
        return false;
    }
    return true;
}
```

Attach them via `Server.middlewares`:

```zig
var server = Mesh.Server{
    // ...
    .middlewares = &.{ auth },
};
```

## Database

`db.DB` is a small union-like handle:

| Constructor       | Behavior                              |
| ----------------- | ------------------------------------- |
| `DB.fromDDB(p)`   | Wraps a real `ddb.DB`. `save()` works.|
| `DB.fromVoid(p)`  | No-op. `save()` does nothing.         |
| `DB.empty()`      | No DB at all. `save()` does nothing.  |

Use `db.asDdb()` to fetch the real handle, or `db.isReal()` to check.

If a real DB is provided and a worker thread starts successfully, `Server` saves it roughly every 5 seconds.

## JSON

`json.parseFromSlice` and `json.parseFromBody` decode JSON into a Zig type. They accept any allocator - an arena is recommended.

```zig
const User = struct { id: u32, name: []const u8 };

var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

const user = try json.parseFromSlice(User, arena.allocator(), body_bytes);
```

For requests, `parseFromBody` sends a proper error response on failure and returns `null`.

## Responses

Helpers in `response.zig`:

- `sendBody(r, msg)` - 200 OK with body.
- `sendError(r, status, msg)` - generic status + message.
- `sendErrorPrint(r, status, allocator, fmt, args)` - formatted error.
- `sendBadRequest(r, msg)` - 400.
- `sendInternalServerError(r, msg)` - 500.
- `notFound(r, allocator, path)` - 404 with the path.
- `getParamStrSave(r, allocator, name)` - param lookup with error reporting.

## Server options

| Field         | Default  | Description                          |
| ------------- | -------- | ------------------------------------ |
| `port`        | `8080`   | Listening port.                      |
| `threads`     | `4`      | Worker threads for zap.              |
| `log`         | `true`   | Enable zap request logging.          |
| `middlewares` | `&.{}`   | Middleware chain.                    |
| `db`          | -        | `DB` handle.                         |
| `io`          | -        | `std.Io` for the background worker.  |

`start()` blocks (it calls `zap.start`). Call `stop()` from another thread or after the listener returns to shut down the worker and clear static state.

## Installation

main branch:
```
zig fetch --save https://github.com/Neon32eeee/mesh/archive/refs/heads/main.tar.gz
```

build.zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "myproject",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const mesh = b.dependency("mesh", .{
        .target = target,
        .optimize = optimize,
    });

    const mesh_module = b.createModule(.{
        .root_source_file = mesh.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("Mesh", mesh_module);
    b.installArtifact(exe);
}
```

## Commands

1. Run main
```
zig build run
```

2. Run tests
```
zig build test
```

### Examples

All examples live under `examples/` and can be run individually:

1. No DB version
```
zig build run-no_db_version
```

2. DB version
```
zig build run-db_version
```

3. JSON
```
zig build run-json
```

4. Params
```
zig build run-params
```

5. Response
```
zig build run-response
```

6. Middleware
```
zig build run-middleware
```

Or run all examples at once:
```
zig build example
```

## More

More details at the [Wiki](https://github.com/Neon32eeee/mesh/wiki).
