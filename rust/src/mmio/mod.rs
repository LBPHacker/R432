pub mod reg;
pub mod term;

unsafe extern "C" {
    //#[link_name = "filt_input"]
    // pub safe static filt_input: reg::R32;

    //#[link_name = "filt_output"]
    // pub safe static filt_output: reg::W32;

    //#[link_name = "inst_input"]
    // pub safe static inst_input: reg::R32;

    //#[link_name = "inst_output"]
    // pub safe static inst_output: reg::W32;

    #[link_name = "random_source"]
    pub safe static random_source: reg::R32;

    #[link_name = "frame_clock"]
    pub safe static frame_clock: reg::R32;

    #[link_name = "terminal"]
    pub safe static terminal: term::Terminal;
}
