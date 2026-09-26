const std = @import("std");
const Io = std.Io;
const Permissions = std.Io.File.Permissions;
const stringToEnum = std.meta.stringToEnum;
const fatal = std.process.fatal;

const usage =
    \\ Usage: zig [command] [options]
    \\
    \\ new          Create a new markdown scratchpad, and open it using the default text editor
    \\ list         List existing scratchpads
    \\ config       Print the configuration file path and contents
    \\
    \\ General commands
    \\
    \\ help         Display executable usage information and exit
    \\
;

const relative_data_dir_path = "/.local/share/scratchpad/";

const Cmd = enum {
    help,
    new,
    open,
    list,
    delete,
    config,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    var data_dir: []u8 = undefined;

    const home_folder = init.environ_map.get("HOME");
    if (home_folder) |home_path| {
        data_dir = try std.mem.concat(
            arena,
            u8,
            &.{ home_path, relative_data_dir_path },
        );
    } else {
        std.log.info("$HOME directory path not set", .{});
        fatal("set the HOME directory path", .{});
    }

    const editor = init.environ_map.get("EDITOR") orelse "nano";

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);

    if (args.len <= 1) {
        std.log.info("{s}", .{usage});
        fatal("expected command argument", .{});
    }

    const cmd = args[1];

    switch (stringToEnum(Cmd, cmd) orelse {
        std.log.info("{s}", .{usage});
        fatal("unexpected command argument: {s}", .{cmd});
    }) {
        Cmd.help => {
            std.log.info("{s}", .{usage});
            return;
        },
        Cmd.new => {
            if (args.len <= 2) {
                std.log.info("Please specify the filename of the created scratchpad", .{});
                return;
            } else if (args.len > 3) {
                std.log.info("usage: scratchpad new <filename>", .{});
                return;
            }

            createScratchpad(editor, data_dir, args[2], io, arena) catch |err| {
                std.log.err("{s}", .{@errorName(err)});
            };
        },
        Cmd.open => {
            if (args.len <= 2) {
                std.log.info("Please specify the filename of the scratchpad being opened", .{});
                return;
            } else if (args.len > 3) {
                std.log.info("usage: scratchpad open <filename>", .{});
                return;
            }

            openScratchpad(editor, data_dir, args[2], io, arena) catch |err| {
                std.log.err("{s}", .{@errorName(err)});
            };
        },
        Cmd.delete => {
            if (args.len <= 2) {
                std.log.info("Please specify the filename of the scratchpad being delete", .{});
                return;
            } else if (args.len > 3) {
                std.log.info("usage: scratchpad delete <filename>", .{});
                return;
            }

            deleteScratchpad(data_dir, args[2], io, arena) catch |err| {
                std.log.err("{s}", .{@errorName(err)});
            };
        },
        Cmd.list => {
            if (args.len != 2) {
                std.log.info("{s}", .{usage});
                fatal("unexpected command argument: {s}", .{args[2]});
            }

            listScratchpads(data_dir, io, arena) catch |err| {
                std.log.err("{s}", .{@errorName(err)});
            };
        },

        Cmd.config => {},
    }
}

fn createScratchpad(editor: []const u8, absolute_data_dir_path: []const u8, filename: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    std.Io.Dir.createDirAbsolute(io, absolute_data_dir_path, .default_dir) catch |err| {
        if (err != std.Io.Dir.CreateDirError.PathAlreadyExists) {
            return err;
        }
    };

    const dir = try Io.Dir.openDirAbsolute(io, absolute_data_dir_path, .{});

    const filename_with_extension = try std.mem.concat(allocator, u8, &.{ filename, ".md" });
    const file = Io.Dir.createFile(dir, io, filename_with_extension, .{ .exclusive = true }) catch |err| {
        if (err == Io.File.OpenError.PathAlreadyExists) {
            std.log.err("A scratchpad with this name already exists", .{});
            std.process.exit(1);
        } else return err;
    };

    const created_file_name = try allocator.alloc(u8, std.fs.max_path_bytes);
    defer allocator.free(created_file_name);

    const filename_len = try file.realPath(io, created_file_name);

    // Open created scratchpad with text editor
    var child_process = try std.process.spawn(
        io,
        .{ .argv = &.{ editor, created_file_name[0..filename_len] } },
    );
    _ = try child_process.wait(io);
}

fn listScratchpads(absolute_data_dir_path: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    const data_dir = try Io.Dir.openDirAbsolute(io, absolute_data_dir_path, .{ .iterate = true });

    const stdout_buf = try allocator.alloc(u8, 1024);
    defer allocator.free(stdout_buf);

    var stdout_writer = std.Io.File.Writer.init(.stdout(), io, stdout_buf);
    const writer = &stdout_writer.interface;

    var header = try std.ArrayList(u8).initCapacity(allocator, 1024);
    defer header.deinit(allocator);

    try header.appendSlice(allocator, "Scratchpads in directory ");
    try header.appendSlice(allocator, absolute_data_dir_path);
    try header.appendSlice(allocator, ":\n");

    try writer.writeAll(header.items);
    var file_iter = data_dir.iterate();
    var idx: u32 = 1;
    var idx_str_buf: [32]u8 = undefined;
    while (try file_iter.next(io)) |file| : (idx += 1) {
        const str_idx = try std.fmt.bufPrint(&idx_str_buf, "{d}", .{idx});
        try writer.writeAll(str_idx);
        try writer.writeAll(". ");
        try writer.writeAll(file.name);
        try writer.writeAll("\n");
    }

    try stdout_writer.flush();
}

fn openScratchpad(editor: []const u8, absolute_data_dir_path: []const u8, filename: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    const data_dir = try Io.Dir.openDirAbsolute(
        io,
        absolute_data_dir_path,
        .{ .iterate = true },
    );

    var file_iter = data_dir.iterate();

    var found_scratchpad = false;
    while (try file_iter.next(io)) |file| {
        if (std.mem.eql(u8, file.name, filename)) {
            found_scratchpad = true;
            break;
        }
    }

    if (!found_scratchpad) {
        std.log.info("Scratchpad {s} not found", .{filename});
        try listScratchpads(absolute_data_dir_path, io, allocator);
        return;
    }

    const absolute_scratchpad_path = try std.mem.concat(
        allocator,
        u8,
        &.{ absolute_data_dir_path, filename },
    );

    var child_process = try std.process.spawn(
        io,
        .{ .argv = &.{ editor, absolute_scratchpad_path } },
    );
    _ = try child_process.wait(io);
}

fn deleteScratchpad(absolute_data_dir_path: []const u8, filename: []const u8, io: Io, allocator: std.mem.Allocator) !void {
    const data_dir = try Io.Dir.openDirAbsolute(io, absolute_data_dir_path, .{ .iterate = true });

    var file_iter = data_dir.iterate();

    var found_scratchpad = false;
    while (try file_iter.next(io)) |file| {
        if (std.mem.eql(u8, file.name, filename)) {
            found_scratchpad = true;
            break;
        }
    }

    if (!found_scratchpad) {
        std.log.info("Scratchpad {s} not found", .{filename});
        try listScratchpads(absolute_data_dir_path, io, allocator);
        return;
    }

    try data_dir.deleteFile(io, filename);

    std.log.info("Successfully deleted scratchpad {s}", .{filename});
}
