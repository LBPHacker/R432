use fix::typenum::consts::{N8, U2};
use fix::Fix;

use crate::demos::clear_screen;
use crate::mmio;
use crate::mmio::term::{Colour, Pixel, PixelPos};
use crate::time;

type Fx = Fix<i32, U2, N8>;

const SCREEN_CENTER: i32 = 128;
const CUBE_RADIUS: i32 = 20;
const CAMERA_Z: i32 = 78;
const PROJECTION_SCALE: i32 = 72 / 2;
const EDGES: [(usize, usize); 12] = [
    (0, 1),
    (1, 3),
    (3, 2),
    (2, 0),
    (4, 5),
    (5, 7),
    (7, 6),
    (6, 4),
    (0, 4),
    (1, 5),
    (2, 6),
    (3, 7),
];
const SIN: [i32; 64] = [
    0, 25, 50, 74, 98, 121, 142, 162, 181, 198, 213, 226, 237, 245, 251, 255, 256, 255, 251, 245,
    237, 226, 213, 198, 181, 162, 142, 121, 98, 74, 50, 25, 0, -25, -50, -74, -98, -121, -142,
    -162, -181, -198, -213, -226, -237, -245, -251, -255, -256, -255, -251, -245, -237, -226, -213,
    -198, -181, -162, -142, -121, -98, -74, -50, -25,
];

pub fn draw_line(start: PixelPos, end: PixelPos, colour: Colour) {
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
        mmio::terminal.plotpix(Pixel {
            pos: PixelPos {
                x: x0 as u8,
                y: y0 as u8,
            },
            color: colour,
        });

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

#[derive(Clone, Copy, Default)]
struct Vec3 {
    x: Fx,
    y: Fx,
    z: Fx,
}

pub fn run() {
    let vertices = [
        Vec3::new(-CUBE_RADIUS, -CUBE_RADIUS, -CUBE_RADIUS),
        Vec3::new(CUBE_RADIUS, -CUBE_RADIUS, -CUBE_RADIUS),
        Vec3::new(-CUBE_RADIUS, CUBE_RADIUS, -CUBE_RADIUS),
        Vec3::new(CUBE_RADIUS, CUBE_RADIUS, -CUBE_RADIUS),
        Vec3::new(-CUBE_RADIUS, -CUBE_RADIUS, CUBE_RADIUS),
        Vec3::new(CUBE_RADIUS, -CUBE_RADIUS, CUBE_RADIUS),
        Vec3::new(-CUBE_RADIUS, CUBE_RADIUS, CUBE_RADIUS),
        Vec3::new(CUBE_RADIUS, CUBE_RADIUS, CUBE_RADIUS),
    ];
    let mut angle = 0usize;

    loop {
        if mmio::terminal.read_keyboard() != 0 {
            return;
        }

        let sin_y = sin(angle);
        let cos_y = cos(angle);
        let sin_x = sin(angle.wrapping_mul(3) / 2);
        let cos_x = cos(angle.wrapping_mul(3) / 2);
        let mut projected = [PixelPos::default(); 8];

        for i in 0..vertices.len() {
            projected[i] = project(rotate_x(rotate_y(vertices[i], sin_y, cos_y), sin_x, cos_x));
        }

        clear_screen();
        draw_cube(projected, Colour::C11);
        angle = angle.wrapping_add(1);

        time::sleep_for(1);
    }
}

impl Vec3 {
    fn new(x: i32, y: i32, z: i32) -> Self {
        Self {
            x: fx_int(x),
            y: fx_int(y),
            z: fx_int(z),
        }
    }
}

fn fx_int(value: i32) -> Fx {
    Fx::new(value << 8)
}

fn fixed_mul(a: Fx, b: Fx) -> Fx {
    Fix::new((a.bits * b.bits) >> 8)
}

fn sin(angle: usize) -> Fx {
    Fx::new(SIN[angle & 63])
}

fn cos(angle: usize) -> Fx {
    sin(angle.wrapping_add(16))
}

fn rotate_y(v: Vec3, sin: Fx, cos: Fx) -> Vec3 {
    Vec3 {
        x: fixed_mul(v.x, cos) + fixed_mul(v.z, sin),
        y: v.y,
        z: fixed_mul(v.z, cos) - fixed_mul(v.x, sin),
    }
}

fn rotate_x(v: Vec3, sin: Fx, cos: Fx) -> Vec3 {
    Vec3 {
        x: v.x,
        y: fixed_mul(v.y, cos) - fixed_mul(v.z, sin),
        z: fixed_mul(v.y, sin) + fixed_mul(v.z, cos),
    }
}

fn project(v: Vec3) -> PixelPos {
    let z = ((v.z.bits >> 8) + CAMERA_Z).max(1);
    let x = SCREEN_CENTER + (((v.x.bits >> 8) * PROJECTION_SCALE) / z);
    let y = SCREEN_CENTER - (((v.y.bits >> 8) * PROJECTION_SCALE) / z);

    PixelPos {
        x: x.clamp(0, 255) as u8,
        y: y.clamp(0, 255) as u8,
    }
}

fn draw_cube(points: [PixelPos; 8], colour: Colour) {
    for &(a, b) in EDGES.iter() {
        draw_line(points[a], points[b], colour);
    }
}
