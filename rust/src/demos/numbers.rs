use crate::mmio;
use crate::printer::Printer;
use crate::time;

pub fn run(printer: &mut Printer) {
    loop {
        if mmio::terminal.read_keyboard() != 0 {
            return;
        }

        printer.print("F: ");
        print_u32_decimal(printer, time::now());
        printer.print(" R: 0x");
        print_u32_hex(printer, mmio::random_source.read());
        printer.print("\n");
    }
}

fn print_u32_decimal(printer: &mut Printer, mut value: u32) {
    let mut buffer = [0u8; 10];
    let mut len = 0usize;

    if value == 0 {
        printer.print("0");
        return;
    }

    while value != 0 {
        buffer[len] = b'0' + (value % 10) as u8;
        value /= 10;
        len += 1;
    }

    while len != 0 {
        len -= 1;
        print_byte(printer, buffer[len]);
    }
}

fn print_u32_hex(printer: &mut Printer, value: u32) {
    const LUT: &[u8; 16] = b"0123456789ABCDEF";

    for shift in (0..32).step_by(4).rev() {
        print_byte(printer, LUT[((value >> shift) & 0xF) as usize]);
    }
}

fn print_byte(printer: &mut Printer, byte: u8) {
    let buffer = [byte];
    let text = unsafe { core::str::from_utf8_unchecked(&buffer) };
    printer.print(text);
}
