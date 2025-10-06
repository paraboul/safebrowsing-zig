const BitReader = @This();

bit_pos: u32 = 0,
buffer: [] const u8,

pub fn init(buffer: [] const u8) BitReader {
    return .{
        .buffer = buffer
    };
}

pub inline fn readBitAtPos(self: *const BitReader, pos: u64) u1 {
    const byte = pos / 8;
    const reminder : u3 = @intCast(pos % 8);

    return @intCast((self.buffer[byte] >> reminder) & 1);
}

pub fn readUnary(self: *BitReader) u16 {
    var bits_read : u16 = 0;

    while (self.readBitAtPos(bits_read + self.bit_pos) != 0) : (bits_read += 1) {}

    self.bit_pos += bits_read + 1;

    return bits_read;
}

pub fn readNBits(self: *BitReader, T: type, count: u32) T {
    var bits : T = 0;

    for (0..count) |p| {
        const b = self.readBitAtPos(self.bit_pos + p);

        bits = bits | (@as(T, b) << @intCast(p));
    }

    self.bit_pos += count;

    return bits;
}
