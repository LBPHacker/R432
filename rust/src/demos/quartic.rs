use fix::typenum::consts::{N8, U2};
use fix::Fix;

use crate::demos::clear_screen;
use crate::mmio;
use crate::mmio::term::{Colour, Pixel, PixelPos};
use crate::printer::Printer;

type Fx = Fix<i32, U2, N8>;

const SCREEN_MIN: i32 = 0;
const SCREEN_MAX: i32 = 255;
const X_MAX: i32 = 8;
const X_MIN: i32 = -8;
const Y_MAX: i32 = 12;
const Y_MIN: i32 = -8;

pub fn run(printer: &mut Printer) {
    printer.clear();
    printer.print("quartic plotter\n");
    printer.print("\ny = ax^4 + bx^3 + cx^2 + dx + e\n\n");

    printer.print("plot bounds:\n");
    printer.print("x: ");
    print_i32_decimal(printer, X_MIN);
    printer.print(" to ");
    print_i32_decimal(printer, X_MAX);
    printer.print("\ny: ");
    print_i32_decimal(printer, Y_MIN);
    printer.print(" to ");
    print_i32_decimal(printer, Y_MAX);
    printer.print("\n\n");
    printer.print("press any key after plotted\n\n");
    printer.print_with_breaks("out of bounds y will be shown for progress\n\n");

    let a = read_coefficient(printer, "a");
    let b = read_coefficient(printer, "b");
    let c = read_coefficient(printer, "c");
    let d = read_coefficient(printer, "d");
    let e = read_coefficient(printer, "e");

    clear_screen();

    draw_axes();
    plot_quartic(fx_int(a), fx_int(b), fx_int(c), fx_int(d), fx_int(e));

    mmio::terminal.read_blocking();
}

fn read_coefficient(printer: &mut Printer, name: &str) -> i32 {
    let mut buffer = [0u8; 11];

    printer.print(name);
    printer.print(" = ");
    let len = printer.read_text_buffer(&mut buffer, valid_i32_prefix);

    parse_i32(&buffer[..len])
}

fn valid_i32_prefix(input: &[u8]) -> bool {
    if input.is_empty() {
        return true;
    }

    for (i, &byte) in input.iter().enumerate() {
        match byte {
            b'-' if i == 0 => {}
            b'0'..=b'9' => {}
            _ => return false,
        }
    }

    true
}

fn parse_i32(input: &[u8]) -> i32 {
    let mut value = 0i32;
    let mut negative = false;

    for (i, &byte) in input.iter().enumerate() {
        if byte == b'-' && i == 0 {
            negative = true;
        } else {
            value = value
                .saturating_mul(10)
                .saturating_add((byte - b'0') as i32);
        }
    }

    if negative {
        -value
    } else {
        value
    }
}

fn plot_quartic(a: Fx, b: Fx, c: Fx, d: Fx, e: Fx) {
    let mut previous = None;

    for screen_x in 0..=u8::MAX {
        let x = screen_x_to_graph_x(screen_x);
        let y = fixed_mul(fixed_mul(fixed_mul(fixed_mul(a, x) + b, x) + c, x) + d, x) + e;
        let screen_y = graph_y_to_screen_y(y);

        let screen_y = screen_y.clamp(SCREEN_MIN, SCREEN_MAX);
        let point = PixelPos {
            x: screen_x,
            y: screen_y as u8,
        };

        if let Some(start) = previous {
            draw_line(start, point, Colour::C10);
        } else {
            plot_pixel(point.x, point.y, Colour::C10);
        }

        previous = Some(point);
        
    }
}

fn draw_axes() {
    let x_axis_y = graph_y_to_screen_y(fx_int(0)).clamp(SCREEN_MIN, SCREEN_MAX) as u8;
    let y_axis_x = graph_x_to_screen_x(fx_int(0)).clamp(SCREEN_MIN, SCREEN_MAX) as u8;

    draw_line(
        PixelPos {
            x: SCREEN_MIN as u8,
            y: x_axis_y,
        },
        PixelPos {
            x: SCREEN_MAX as u8,
            y: x_axis_y,
        },
        Colour::C8,
    );
    draw_line(
        PixelPos {
            x: y_axis_x,
            y: SCREEN_MIN as u8,
        },
        PixelPos {
            x: y_axis_x,
            y: SCREEN_MAX as u8,
        },
        Colour::C8,
    );
}

fn draw_line(start: PixelPos, end: PixelPos, colour: Colour) {
    let mut x0 = start.x as i32;
    let mut y0 = start.y as i32;
    let x1 = end.x as i32;
    let y1 = end.y as i32;
    let dx = (x1 - x0).abs();
    let dy = -(y1 - y0).abs();
    let sx = if x0 < x1 { 1 } else { -1 };
    let sy = if y0 < y1 { 1 } else { -1 };
    let mut err = dx + dy;

    loop {
        plot_pixel(x0 as u8, y0 as u8, colour);

        if x0 == x1 && y0 == y1 {
            break;
        }

        let twice_err = err * 2;
        if twice_err >= dy {
            err += dy;
            x0 += sx;
        }
        if twice_err <= dx {
            err += dx;
            y0 += sy;
        }
    }
}

fn plot_pixel(x: u8, y: u8, colour: Colour) {
    mmio::terminal.plotpix(Pixel {
        pos: PixelPos { x, y },
        color: colour,
    });
}

fn fx_int(value: i32) -> Fx {
    Fx::new(value << 8)
}

fn fixed_mul(a: Fx, b: Fx) -> Fx {
    Fix::new((a.bits * b.bits) >> 8)
}

fn screen_x_to_graph_x(screen_x: u8) -> Fx {
    let range = X_MAX - X_MIN;
    Fix::new((X_MIN << 8) + (((screen_x as i32 * range) << 8) / SCREEN_MAX))
}

const fn graph_x_to_screen_x(x: Fx) -> i32 {
    ((x.bits - (X_MIN << 8)) * SCREEN_MAX) / ((X_MAX - X_MIN) << 8)
}

const fn graph_y_to_screen_y(y: Fx) -> i32 {
    SCREEN_MAX - ((y.bits - (Y_MIN << 8)) * SCREEN_MAX) / ((Y_MAX - Y_MIN) << 8)
}

fn print_i32_decimal(printer: &mut Printer, value: i32) {
    if value < 0 {
        print_byte(printer, b'-');
        print_u32_decimal(printer, value.unsigned_abs());
    } else {
        print_u32_decimal(printer, value as u32);
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

fn print_byte(printer: &mut Printer, byte: u8) {
    let buffer = [byte];
    let text = unsafe { core::str::from_utf8_unchecked(&buffer) };
    printer.print(text);
}
