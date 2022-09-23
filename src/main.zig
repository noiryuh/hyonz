const builtin = @import("builtin");

pub const base16 = @import("codec/base16/main.zig");

comptime {
    if (builtin.is_test) {
        _ = base16;
    }
}
