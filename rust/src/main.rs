#![no_std]
#![no_main]

pub mod demos;
pub mod mmio;
pub mod panic;
pub mod printer;
pub mod start;
pub mod time;

use crate::printer::Printer;

#[unsafe(no_mangle)]
pub fn main() {
    let mut printer = Printer::new(&mmio::terminal, 32, 32);
    printer.init();

    loop {
        mmio::terminal.reset_keyboard();
        printer.clear();
        printer.print("Rust demos\n\n");
        printer.print("1 rotating cube\n");
        printer.print("2 frame/rand\n");
        printer.print("3 quartic plotter\n");
        printer.print("\npress key to select\n");
        printer.print("press any key to exit demo");


        let input = loop {
            let input = (mmio::terminal.read_blocking() & 0xFF) as u8;

            match input {
                b'1' | b'2' | b'3' => {
                    printer.clear();
                    mmio::terminal.reset_keyboard();
                    break input;
                }
                _ => {}
            }
        };

        match input {
            b'1' => demos::cube::run(),
            b'2' => demos::numbers::run(&mut printer),
            b'3' => demos::quartic::run(&mut printer),
            _ => {}
        }
    }
}