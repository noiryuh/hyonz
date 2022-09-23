const std = @import("std");
const ascii = std.ascii;
const testing = std.testing;

const Allocator = std.mem.Allocator;

//==============================================
//==============================================

/// A standard (rfc4868) lower-case codec
pub const standard_lower = Codec(.{ .alphabet = "0123456789abcdef".* });

/// A standard (rfc4868) upper-case codec
pub const standard_upper = Codec(.{ .alphabet = "0123456789ABCDEF".* });

//==============================================
// Codec implementation
//==============================================

pub const CodecOptions = struct {
    alphabet: [16]u8,
};

pub fn Codec(comptime codec_options: CodecOptions) type {
    return struct {
        pub const alphabet = codec_options.alphabet;

        pub const Encoder = EncoderAdvanced(.{ .alphabet = alphabet });
        pub const Decoder = DecoderAdvanced(.{ .alphabet = alphabet });
    };
}

//==============================================
// Encoder implementation
//==============================================

pub const EncoderOptions = struct {
    alphabet: [16]u8,
};

pub fn EncoderAdvanced(comptime encoder_options: EncoderOptions) type {
    validateAlphabet(encoder_options.alphabet);
    const alphabet = encoder_options.alphabet;

    return struct {
        /// Return needed size for encoding `src` bytes
        pub fn calcSize(src_len: usize) usize {
            return src_len * 2;
        }

        /// Return needed size for encoding `src` bytes
        pub fn calcSizeForSlice(src: []const u8) usize {
            return calcSize(src.len);
        }

        pub fn encodeBuffer(src: []const u8, dst: []u8) []const u8 {
            const encode_len = calcSizeForSlice(src);
            std.debug.assert(encode_len <= dst.len);

            var i: usize = 0;
            for (src) |c| {
                defer i += 2;
                dst[i + 0] = alphabet[c >> 4];
                dst[i + 1] = alphabet[c & 0x0F];
            }
            return dst[0..encode_len];
        }

        pub fn encodeAlloc(allocator: Allocator, src: []const u8) ![]const u8 {
            var buf = try allocator.alloc(u8, calcSizeForSlice(src));
            errdefer allocator.free(buf);

            return encodeBuffer(src, buf);
        }

        pub fn encodeComptime(comptime src: []const u8) []const u8 {
            comptime {
                var result: []const u8 = "";
                for (src) |c| {
                    result = result ++ [_]u8{alphabet[c >> 4]};
                    result = result ++ [_]u8{alphabet[c & 0x0F]};
                }
                return result;
            }
        }

        pub fn encodeWriter(src: []const u8, writer: anytype) !void {
            for (src) |c| {
                try writer.writeByte(alphabet[c >> 4]);
                try writer.writeByte(alphabet[c & 0x0F]);
            }
        }
    };
}

//==============================================
// Decoder implementation
//==============================================

pub const DecoderOptions = struct {
    alphabet: [16]u8,
};

pub fn DecoderAdvanced(comptime decoder_options: DecoderOptions) type {
    validateAlphabet(decoder_options.alphabet);
    const alphabet = decoder_options.alphabet;

    return struct {
        pub const CalcSizeError = error{
            InvalidLength,
        };

        /// Return needed size for decoding `src` bytes
        pub fn calcSize(src_len: usize) CalcSizeError!usize {
            if (src_len % 2 != 0) {
                return error.InvalidLength;
            }
            return @divExact(src_len, 2);
        }

        /// Return needed size for decoding `src` bytes
        pub fn calcSizeForSlice(src: []const u8) CalcSizeError!usize {
            return try calcSize(src.len);
        }

        pub const Options = struct {
            has_mixed_case: bool = true,
        };

        // NOTE: waiting for inline parameter (https://github.com/ziglang/zig/issues/7772)
        pub fn decodeBuffer(src: []const u8, dst: []u8, options: Options) ![]const u8 {
            const decode_len = try calcSizeForSlice(src);
            std.debug.assert(decode_len <= dst.len);

            const t0 = generateLookupTable(options);

            var i: usize = 1;
            var j: usize = 0;
            while (i < src.len) : (i += 2) {
                defer j += 1;

                const c1 = t0[src[i - 1]];
                if (c1 == invalid_byte)
                    return error.InvalidByte;
                const c2 = t0[src[i - 0]];
                if (c2 == invalid_byte)
                    return error.InvalidByte;

                dst[j] = (c1 << 4) | c2;
            }
            return dst[0..decode_len];
        }

        // NOTE: waiting for inline parameter (https://github.com/ziglang/zig/issues/7772)
        pub fn decodeAlloc(allocator: Allocator, src: []const u8, options: Options) ![]const u8 {
            var buf = try allocator.alloc(u8, try calcSizeForSlice(src));
            errdefer allocator.free(buf);

            return try decodeBuffer(src, buf, options);
        }

        // NOTE: waiting for inline parameter (https://github.com/ziglang/zig/issues/7772)
        pub fn decodeComptime(comptime src: []const u8, comptime options: Options) ![]const u8 {
            comptime {
                const t0 = generateLookupTable(options);

                var result: []const u8 = "";

                var i: usize = 1;
                while (i < src.len) : (i += 2) {
                    const c1 = t0[src[i - 1]];
                    if (c1 == invalid_byte)
                        return error.InvalidByte;
                    const c2 = t0[src[i - 0]];
                    if (c2 == invalid_byte)
                        return error.InvalidByte;

                    result = result ++ [_]u8{(c1 << 4) | c2};
                }

                return result;
            }
        }

        // NOTE: waiting for inline parameter (https://github.com/ziglang/zig/issues/7772)
        pub fn decodeWriter(src: []const u8, writer: anytype, options: Options) !void {
            const t0 = generateLookupTable(options);

            var i: usize = 1;
            while (i < src.len) : (i += 2) {
                const c1 = t0[src[i - 1]];
                if (c1 == invalid_byte)
                    return error.InvalidByte;
                const c2 = t0[src[i - 0]];
                if (c2 == invalid_byte)
                    return error.InvalidByte;

                try writer.writeByte((c1 << 4) | c2);
            }
        }

        const invalid_byte = 0xFF;

        // NOTE: waiting for inline parameter (https://github.com/ziglang/zig/issues/7772)
        fn generateLookupTable(options: Options) [256]u8 {
            if (options.has_mixed_case) {
                return comptime blk: {
                    var result = [_]u8{invalid_byte} ** 256;
                    for (alphabet) |c, i| {
                        result[ascii.toLower(c)] = i;
                        result[ascii.toUpper(c)] = i;
                    }
                    break :blk result;
                };
            }

            return comptime blk: {
                var result = [_]u8{invalid_byte} ** 256;
                for (alphabet) |c, i| {
                    result[c] = i;
                }
                break :blk result;
            };
        }
    };
}

//==============================================
// Helper functions
//==============================================

fn validateAlphabet(comptime alphabet: [16]u8) void {
    var char_in_alphabet = [_]bool{false} ** 256;
    for (alphabet) |c| {
        // For ignore-case purpose, turn char to lower-case
        const lower_char = ascii.toLower(c);

        if (char_in_alphabet[lower_char]) {
            @compileError("alphabet cannot have same character '" ++ [_]u8{c} ++ "' regardless of case");
        }
        char_in_alphabet[lower_char] = true;
    }
}

//==============================================
// Test cases
//==============================================

test "Encoder.calcSize" {
    const text = "The quick brown fox jumps over the lazy dog !?";

    try testing.expectEqual(@as(usize, 92), standard_lower.Encoder.calcSize(text.len));
    try testing.expectEqual(@as(usize, 92), standard_lower.Encoder.calcSizeForSlice(text));

    try testing.expectEqual(@as(usize, 92), standard_upper.Encoder.calcSize(text.len));
    try testing.expectEqual(@as(usize, 92), standard_upper.Encoder.calcSizeForSlice(text));
}

test "standard.encodeBuffer" {
    const text = "The quick brown fox jumps over the lazy dog !?";

    {
        var buffer: [100]u8 = undefined;
        try testing.expectEqualStrings(
            "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f",
            standard_lower.Encoder.encodeBuffer(text, &buffer),
        );
    }
    {
        var buffer: [100]u8 = undefined;
        try testing.expectEqualStrings(
            "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F",
            standard_upper.Encoder.encodeBuffer(text, &buffer),
        );
    }
}

test "standard.encodeAlloc" {
    const allocator = testing.allocator;
    const text = "The quick brown fox jumps over the lazy dog !?";

    {
        const result = try standard_lower.Encoder.encodeAlloc(allocator, text);
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f",
            result,
        );
    }
    {
        const result = try standard_upper.Encoder.encodeAlloc(allocator, text);
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F",
            result,
        );
    }
}

test "standard.encodeComptime" {
    const text = "The quick brown fox jumps over the lazy dog !?";

    try testing.expectEqualStrings(
        "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f",
        standard_lower.Encoder.encodeComptime(text),
    );
    try testing.expectEqualStrings(
        "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F",
        standard_upper.Encoder.encodeComptime(text),
    );
}

test "standard.encodeWriter" {
    const text = "The quick brown fox jumps over the lazy dog !?";
    const encode_len = standard_lower.Encoder.calcSizeForSlice(text);

    {
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, encode_len);
        defer list.deinit();

        try standard_lower.Encoder.encodeWriter(text, list.writer());
        try testing.expectEqualStrings(
            "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f",
            list.items[0..encode_len],
        );
    }
    {
        var list = try std.ArrayList(u8).initCapacity(testing.allocator, encode_len);
        defer list.deinit();

        try standard_upper.Encoder.encodeWriter(text, list.writer());
        try testing.expectEqualStrings(
            "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F",
            list.items[0..encode_len],
        );
    }
}

test "Decoder.calcSize" {
    const text = "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f";

    try testing.expectEqual(@as(usize, 46), try standard_lower.Decoder.calcSize(text.len));
    try testing.expectEqual(@as(usize, 46), try standard_lower.Decoder.calcSizeForSlice(text));

    try testing.expectEqual(@as(usize, 46), try standard_upper.Decoder.calcSize(text.len));
    try testing.expectEqual(@as(usize, 46), try standard_upper.Decoder.calcSizeForSlice(text));
}

test "standard.decodeBuffer" {
    {
        const text = "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f";

        var buffer: [100]u8 = undefined;
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_lower.Decoder.decodeBuffer(text, &buffer, .{ .has_mixed_case = false }),
        );
    }
    {
        const text = "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F";

        var buffer: [100]u8 = undefined;
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_upper.Decoder.decodeBuffer(text, &buffer, .{ .has_mixed_case = false }),
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";

        var buffer: [100]u8 = undefined;
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_lower.Decoder.decodeBuffer(text, &buffer, .{}),
        );
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_upper.Decoder.decodeBuffer(text, &buffer, .{}),
        );
    }
}

test "standard.decodeAlloc" {
    const allocator = testing.allocator;
    {
        const text = "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f";

        const result = try standard_lower.Decoder.decodeAlloc(allocator, text, .{ .has_mixed_case = false });
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            result,
        );
    }
    {
        const text = "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F";

        const result = try standard_upper.Decoder.decodeAlloc(allocator, text, .{ .has_mixed_case = false });
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            result,
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";

        const result = try standard_lower.Decoder.decodeAlloc(allocator, text, .{});
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            result,
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";

        const result = try standard_upper.Decoder.decodeAlloc(allocator, text, .{});
        defer allocator.free(result);

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            result,
        );
    }
}

test "standard.decodeComptime" {
    {
        const text = "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f";

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_lower.Decoder.decodeComptime(text, .{ .has_mixed_case = false }),
        );
    }
    {
        const text = "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F";

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_upper.Decoder.decodeComptime(text, .{ .has_mixed_case = false }),
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";

        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_lower.Decoder.decodeComptime(text, .{}),
        );
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            try standard_upper.Decoder.decodeComptime(text, .{}),
        );
    }
}

test "standard.decodeWriter" {
    const allocator = testing.allocator;
    {
        const text = "54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f6720213f";
        const decode_len = try standard_lower.Decoder.calcSizeForSlice(text);

        var list = try std.ArrayList(u8).initCapacity(allocator, decode_len);
        defer list.deinit();

        try standard_lower.Decoder.decodeWriter(text, list.writer(), .{ .has_mixed_case = false });
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            list.items[0..decode_len],
        );
    }
    {
        const text = "54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F6720213F";
        const decode_len = try standard_upper.Decoder.calcSizeForSlice(text);

        var list = try std.ArrayList(u8).initCapacity(allocator, decode_len);
        defer list.deinit();

        try standard_upper.Decoder.decodeWriter(text, list.writer(), .{ .has_mixed_case = false });
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            list.items[0..decode_len],
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";
        const decode_len = try standard_lower.Decoder.calcSizeForSlice(text);

        var list = try std.ArrayList(u8).initCapacity(allocator, decode_len);
        defer list.deinit();

        try standard_lower.Decoder.decodeWriter(text, list.writer(), .{});
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            list.items[0..decode_len],
        );
    }
    {
        const text = "54686520717569636B2062726f776e20666F78206a756D7073206F76657220746865206c617A7920646f6720213f";
        const decode_len = try standard_upper.Decoder.calcSizeForSlice(text);

        var list = try std.ArrayList(u8).initCapacity(allocator, decode_len);
        defer list.deinit();

        try standard_upper.Decoder.decodeWriter(text, list.writer(), .{});
        try testing.expectEqualStrings(
            "The quick brown fox jumps over the lazy dog !?",
            list.items[0..decode_len],
        );
    }
}
