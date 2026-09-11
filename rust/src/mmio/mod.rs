pub mod reg;
pub mod term;

unsafe extern "C" {
    // pub safe static filt_input: reg::R32;
    // pub safe static filt_output: reg::W32;
    // pub safe static inst_input: reg::R32;
    // pub safe static inst_output: reg::W32;
    pub safe static random_source: reg::R32;
    pub safe static frame_clock: reg::R32;
    pub safe static terminal: term::Terminal;
}
