use super::*;

#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct Range(u32);

impl Range {
    #[inline(always)]
    pub const fn new(first: u8, last: u8) -> Self {
        Self((first as u32) | ((last as u32) << 5))
    }

    #[inline(always)]
    pub const fn bits(self) -> u32 {
        self.0
    }
}

#[repr(u8)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub enum Colour {
    #[default]
    C0,
    C1,
    C2,
    C3,
    C4,
    C5,
    C6,
    C7,
    C8,
    C9,
    C10,
    C11,
    C12,
    C13,
    C14,
    C15,
}

#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct CellColour(u32);

impl CellColour {
    #[inline(always)]
    pub const fn new(foreground: Colour, background: Colour) -> Self {
        Self(foreground as u32 | ((background as u32) << 4))
    }
}

#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct CursorPosition(u32);

impl CursorPosition {
    #[inline(always)]
    pub const fn new(column: u8, row: u8) -> Self {
        Self(column as u32 | ((row as u32) << 5))
    }

    #[inline(always)]
    pub const fn bits(self) -> u32 {
        self.0
    }
}

#[repr(C)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct PixelPos {
    pub x: u8,
    pub y: u8,
}

#[repr(C, align(4))]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct Pixel {
    pub pos: PixelPos,
    pub color: Colour,
}

#[repr(transparent)]
#[derive(Clone, Copy, PartialEq, Eq, Hash, Debug, Default)]
pub struct ScrollprintFlags(u32);

impl ScrollprintFlags {
    pub const POS_IN_DATA: Self = Self(1 << 6);
    pub const ENABLE_NLCHAR: Self = Self(1 << 5);
    pub const TERM_MODE_SCROLL: Self = Self(1 << 4);
    pub const ENABLE_SCROLLMASK: Self = Self(1 << 3);
    pub const COLUMN_ORIENTED: Self = Self(1 << 2);
    pub const COLOUR_IN_DATA: Self = Self(1 << 1);
    pub const TERM_MODE: Self = Self(1 << 0);

    pub const SIMPLE_TERMINAL: Self =
        Self(Self::ENABLE_NLCHAR.bits() | Self::TERM_MODE_SCROLL.bits() | Self::TERM_MODE.bits());

    #[inline(always)]
    pub const fn pos_in_data() -> Self {
        Self::POS_IN_DATA
    }

    #[inline(always)]
    pub const fn enable_nlchar() -> Self {
        Self::ENABLE_NLCHAR
    }

    #[inline(always)]
    pub const fn term_mode_scroll() -> Self {
        Self::TERM_MODE_SCROLL
    }

    #[inline(always)]
    pub const fn enable_scrollmask() -> Self {
        Self::ENABLE_SCROLLMASK
    }

    #[inline(always)]
    pub const fn column_oriented() -> Self {
        Self::COLUMN_ORIENTED
    }

    #[inline(always)]
    pub const fn colour_in_data() -> Self {
        Self::COLOUR_IN_DATA
    }

    #[inline(always)]
    pub const fn term_mode() -> Self {
        Self::TERM_MODE
    }

    #[inline(always)]
    pub const fn simple_terminal() -> Self {
        Self::SIMPLE_TERMINAL
    }

    #[inline(always)]
    pub const fn bits(self) -> u32 {
        self.0
    }
}

impl core::ops::BitOr for ScrollprintFlags {
    type Output = Self;

    #[inline(always)]
    fn bitor(self, rhs: Self) -> Self::Output {
        Self(self.bits() | rhs.bits())
    }
}

impl core::ops::BitOrAssign for ScrollprintFlags {
    #[inline(always)]
    fn bitor_assign(&mut self, rhs: Self) {
        self.0 |= rhs.bits();
    }
}

// ----------------------------------------------

#[repr(C)]
pub struct Terminal {
    input: reg::R32,
    hrange: reg::W32<Range>,
    vrange: reg::W32<Range>,
    cursor: reg::W32<CursorPosition>,
    nlchar: reg::W32,
    colour: reg::W32<CellColour>,
    scrollmask: reg::W32,
    plotpix: reg::W32<Pixel>,
    padding_1: [reg::Pad32; 0x78],
    scrollprint: [reg::W32; 0x80],
    begin_bitmap: [reg::W32; 0x100],
    char_mem: [reg::W32; 0x200],
    end_bitmap: [reg::W32; 0x400],
}

impl Terminal {
    #[inline(always)]
    pub fn set_horizontal_range(&self, first: u8, last: u8) {
        self.hrange.write(Range::new(first, last));
    }

    #[inline(always)]
    pub fn set_vertical_range(&self, first: u8, last: u8) {
        self.vrange.write(Range::new(first, last));
    }

    #[inline(always)]
    pub fn set_cursor_position(&self, column: u8, row: u8) {
        self.cursor.write(CursorPosition::new(column, row));
    }

    #[inline(always)]
    pub fn set_cell_colour(&self, foreground: Colour, background: Colour) {
        self.colour.write(CellColour::new(foreground, background));
    }

    #[inline(always)]
    pub fn set_newline_char(&self, value: u8) {
        self.nlchar.write(value as u32);
    }

    #[inline(always)]
    pub fn set_scrollmask(&self, value: u32) {
        self.scrollmask.write(value);
    }

    #[inline(always)]
    pub fn scrollprint(&self, flags: ScrollprintFlags, value: u32) {
        self.scrollprint[flags.bits() as usize].write(value);
    }

    #[inline(always)]
    pub fn print_byte(&self, flags: ScrollprintFlags, value: u8) {
        self.scrollprint(flags, value as u32);
    }

    #[inline(always)]
    pub fn plotpix(&self, pixel: Pixel) {
        self.plotpix.write(pixel);
    }

    #[inline(always)]
    pub fn read_keyboard(&self) -> u32 {
        self.input.read()
    }

    #[inline(always)]
    pub fn reset_keyboard(&self) {
        let _ = self.read_keyboard();
    }

    #[inline(always)]
    pub fn read_blocking(&self) -> u32 {
        loop {
            let got = self.read_keyboard();

            if got & 0xFF != 0 {
                return got;
            }
        }
    }
}
