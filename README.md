# hyonz

Various encoding codec implementations written in Zig.


## Usage

In `build.zig`:
```zig
const std = @import("std");
const hyonz = @import("hyonz/build.zig");

pub fn build(b: *std.build.Builder) void {
    // ....
    hyonz.linkPkg(exe);
}
```

In `main.zig`:
```zig
const std = @import("std");

const hyonz = @import("hyonz");
const base16 = hyonz.base16;

pub fn main() !void {
    const x = base16.standard_upper.Encoder.encodeComptime("!?");
    _ = x;
}
```
