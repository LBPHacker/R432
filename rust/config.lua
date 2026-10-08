loadfile("/path/to/r4plot.lua")({
	x = 66,
	y = 200,
	components = {
		{
			type        = "cpu",
			name        = "cpu0",
			cores       = "mimi",
			memory_rows = 64,
			left        = -60,
			top         = 36-48,
			machine_id  = 1000,
			memory_base = 0x400000,
			memory      = "<BIN PATH>",
			start_pc    = 0x400000,
		},
		{
			type          = "terminal",
			name          = "terminal0",
			left          = 140,
			screen_bottom = 110,
			keyboard_top  = 128,
			chars_nh      = 32,
			chars_nv      = 32,
			grvt_cover    = true,
			single_pixel  = true,
			base_address  = 0xE0010000,
			bus = {
				cpu       = "cpu0",
				bus_index = 3,
			},
		},
		{
			type          = "random_source",
			name          = "random_source0",
			left          = 277,
			base_address  = 0xE0060000,
			bus = {
				cpu       = "cpu0",
				bus_index = 3,
			},
		},
		{
			type          = "frame_clock",
			name          = "frame_clock0",
			left          = 240,
			base_address  = 0xE0070000,
			bus = {
				cpu       = "cpu0",
				bus_index = 3,
			},
		},
	},
})
