use crate::mmio::term::{Colour, ScrollprintFlags, Terminal};

pub struct Printer<'a> {
    terminal: &'a Terminal,
    cursor_x: u8,
    cursor_y: u8,
    colour_fg: Colour,
    colour_bg: Colour,
    width: u8,
    height: u8,
}

impl<'a> core::fmt::Write for Printer<'a> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        self.print(s);
        Ok(())
    }
}

impl<'a> Printer<'a> {
    pub const fn new(terminal: &'a Terminal, width: u8, height: u8) -> Self {
        Self {
            terminal,
            cursor_x: 0,
            cursor_y: 0,
            colour_fg: Colour::C15,
            colour_bg: Colour::C0,
            width,
            height,
        }
    }

    pub fn init(&mut self) {
        self.terminal.reset_keyboard();
        self.terminal.set_cell_colour(self.fg(), self.bg());
        self.terminal.set_horizontal_range(0, self.width - 1);
        self.terminal.set_vertical_range(0, self.height - 1);
        self.terminal.set_cursor_position(0, 0);
        self.terminal.set_newline_char(b'\n');
        self.terminal.set_scrollmask(u32::MAX);
    }

    pub fn clear(&mut self) {
        self.set_cursor(0, 0);

        for _ in 0..self.height {
            self.terminal
                .print_byte(ScrollprintFlags::ENABLE_SCROLLMASK, b' ');
        }
    }

    pub fn print(&mut self, text: &str) {
        for byte in text.bytes() {
            self.put(byte);
        }
    }

    pub fn print_with_breaks(&mut self, text: &str) {
        let mut first_word = true;

        for word in text.split(' ') {
            let word_len = word.len();
            let required_space = usize::from(!first_word);

            if self.cursor_x as usize + required_space + word_len > self.width as usize {
                self.put(b'\n');
                first_word = true;
            }

            if !first_word {
                self.put(b' ');
            }

            for byte in word.bytes() {
                self.put(byte);
            }

            first_word = self.cursor_x == 0;
        }
    }

    pub fn newline(&mut self) {
        self.put(b'\n');
    }

    pub fn backspace(&mut self) -> bool {
        if self.cursor_x == 0 {
            return false;
        }

        self.cursor_x -= 1;
        self.terminal
            .set_cursor_position(self.cursor_x, self.cursor_y);
        self.terminal
            .print_byte(ScrollprintFlags::SIMPLE_TERMINAL, b' ');
        self.terminal
            .set_cursor_position(self.cursor_x, self.cursor_y);
        true
    }

    pub fn read_text_buffer<F>(&mut self, buffer: &mut [u8], mut validate: F) -> usize
    where
        F: FnMut(&[u8]) -> bool,
    {
        let mut len = 0usize;

        loop {
            let key = (self.get_char_blink() & 0xFF) as u8;

            match key {
                b'\n' | b'\r' => {
                    self.newline();
                    return len;
                }
                8 | 127 => {
                    if len != 0 {
                        len -= 1;
                        self.backspace();
                    }
                }
                _ if len < buffer.len() => {
                    buffer[len] = key;

                    if validate(&buffer[..=len]) {
                        len += 1;
                        self.put(key);
                    }
                }
                _ => {}
            }
        }
    }

    #[inline(always)]
    pub const fn fg(&self) -> Colour {
        self.colour_fg
    }

    #[inline(always)]
    pub const fn bg(&self) -> Colour {
        self.colour_bg
    }

    #[inline(always)]
    pub const fn cursor_x(&self) -> u8 {
        self.cursor_x
    }

    #[inline(always)]
    pub const fn cursor_y(&self) -> u8 {
        self.cursor_y
    }

    #[inline(always)]
    pub fn set_colour(&mut self, foreground: Colour, background: Colour) {
        self.colour_fg = foreground;
        self.colour_bg = background;
        self.terminal
            .set_cell_colour(self.colour_fg, self.colour_bg);
    }

    #[inline(always)]
    pub fn set_cursor(&mut self, x: u8, y: u8) {
        self.cursor_x = x;
        self.cursor_y = y;
        self.terminal
            .set_cursor_position(self.cursor_x, self.cursor_y);
    }

    pub fn get_char_blink(&mut self) -> u32 {
        const SLEEP_FRAMES: crate::time::Frame = 30;

        let mut fg = self.colour_fg;
        let mut bg = self.colour_bg;

        loop {
            let ch = self.terminal.read_keyboard();

            if ch != 0 {
                self.terminal
                    .set_cell_colour(self.colour_fg, self.colour_bg);
                self.terminal
                    .set_cursor_position(self.cursor_x, self.cursor_y);
                self.terminal.print_byte(ScrollprintFlags::TERM_MODE, b' ');
                self.terminal
                    .set_cursor_position(self.cursor_x, self.cursor_y);
                return ch;
            }

            self.terminal.set_cell_colour(fg, bg);
            self.terminal
                .set_cursor_position(self.cursor_x, self.cursor_y);
            self.terminal.print_byte(ScrollprintFlags::TERM_MODE, b' ');

            crate::time::sleep_for(SLEEP_FRAMES);
            core::mem::swap(&mut fg, &mut bg);
        }
    }

    #[inline(always)]
    fn put(&mut self, byte: u8) -> bool {
        let is_newline = byte == b'\n';

        if is_newline || self.cursor_x == self.width {
            self.cursor_x = 0;

            if self.cursor_y < self.height - 1 {
                self.cursor_y += 1;
            }
        }

        self.terminal
            .print_byte(ScrollprintFlags::SIMPLE_TERMINAL, byte);

        if !is_newline {
            self.cursor_x += 1;
        }

        is_newline
    }
}
