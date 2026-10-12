pub type Frame = u32;

pub fn now() -> Frame {
    crate::mmio::frame_clock.read()
}

pub fn sleep_until(frame: Frame) {
    while now() < frame {
        core::hint::spin_loop();
    }
}

pub fn sleep_for(frames: Frame) {
    sleep_until(now() + frames)
}
