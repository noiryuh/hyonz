const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    _ = b;
}

//==============================================
// Package SDK
//==============================================

/// Return absolute path from this project's root directory which containing this 'build.zig'
pub fn sdkPath(comptime path: []const u8) []const u8 {
    if (std.fs.path.isSep(path[0])) {
        @compileError("'" ++ path ++ "' must be a relative path");
    }
    const root_dir = comptime std.fs.path.dirname(@src().file) orelse ".";
    return root_dir ++ "/" ++ path;
}

/// Convenient to manually import package
pub const pkg = std.build.Pkg{
    .name = "hyonz",
    .source = .{ .path = sdkPath("src/main.zig") },
};

/// Convenient to import package
pub fn linkPkg(exe: *std.build.LibExeObjStep) void {
    exe.addPackage(pkg);
}
