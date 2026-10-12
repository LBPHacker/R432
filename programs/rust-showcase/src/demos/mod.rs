use crate::mmio;

pub mod cube;
pub mod numbers;
pub mod quartic;

pub fn clear_screen() {
    let mut printer = crate::printer::Printer::new(&mmio::terminal, 32, 32);
    printer.clear();
}
