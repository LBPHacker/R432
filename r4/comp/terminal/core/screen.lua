local spaghetti   = require("spaghetti")
local bitx        = require("spaghetti.bitx")
local testbed     = require("spaghetti.testbed")
local common      = require("r4.common")
local comp_common = require("r4.comp.common")
local stack_31_1  = require("r4.comp.stack_31_1").instantiate()

return testbed.module(function(params)
	local param_debug = params.debug == "y"
	local storage_slots = param_debug and 90 or 77
	local opt_params = {
		temp_initial  = 1,
		temp_final    = 0.5,
		temp_loss     = 1e-6,
	}
	if not param_debug then
		opt_params.seed                = { 0x56789ABC, 0x8765432D }
		opt_params.thread_count        = 8
		opt_params.round_length        = 10000
		opt_params.rounds_per_exchange = 10
		opt_params.storage_slot_overhead_penalty = 12
		opt_params.schedule = {
			durations    = { 100000, 200000, 600000,        },
			temperatures = {     10,      2,      1,    0.5 },
		}
	end

	return {
		tag = "core.screen",
		opt_params    = opt_params,
		stacks        = 2,
		storage_slots = storage_slots,
		work_slots    = 25,
		inputs = {
			{ name = "hrange"         , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "vrange"         , index =  2, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "cursor"         , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "nlchar"         , index =  4, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "color"          , index =  5, keepalive = 0x10000000, payload = 0x000000FF, initial = 0x10000000 },
			{ name = "scrollmask_lo"  , index =  6, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "scrollmask_hi"  , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "beginbitmap_lo" , index =  8, keepalive = 0x10000000, payload = 0x07FFFFFF, initial = 0x10000000 },
			{ name = "beginbitmap_hi" , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "written"        , index = 58, keepalive = 0x10000000, payload = 0x00000007, initial = 0x10000000 },
			{ name = "addr_lo"        , index = 59, keepalive = 0x10000000, payload = 0x03FFFFFF, initial = 0x10000000 },
			{ name = "data_lo_addr_hi", index = 60, keepalive = 0x10000000, payload = 0x07FFFFFF, initial = 0x10000000 },
			{ name = "data_hi"        , index = 61, keepalive = 0x10000000, payload = 0x0000FFFF, initial = 0x10000000 },
			{ name = "repeat_data"    , index = 73, keepalive = 0x20000000, payload = 0x1FFFFFFF, initial = 0x20000000 },
		},
		outputs = {
			{ name = "hrange"          , index =  1, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "vrange"          , index =  2, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "cursor"          , index =  3, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "nlchar"          , index =  4, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "color"           , index =  5, keepalive = 0x10000000, payload = 0x000000FF },
			{ name = "scrollmask_lo"   , index =  6, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "scrollmask_hi"   , index =  7, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "beginbitmap_lo"  , index =  8, keepalive = 0x10000000, payload = 0x07FFFFFF },
			{ name = "beginbitmap_hi"  , index =  9, keepalive = 0x10000000, payload = 0x0000FFFF },
			{ name = "cmem_writer"     , index = 48, keepalive = 0x04000000, payload = 0x000007FF },
			{ name = "pixel_plotter"   , index = 51, keepalive = 0x02200000, payload = 0x0003FFFE },
			{ name = "bank_select"     , index = 58, keepalive = 0x1C300000, payload = 0x000FFFFF },
			{ name = "char_select_r_8" , index = 59, keepalive = 0x10000008, payload = 0x00000003 },
			{ name = "char_select_c_12", index = 60, keepalive = 0x10000000, payload = 0x000000FF },
			{ name = "char_select_c_8" , index = 61, keepalive = 0x10000000, payload = 0x0000007F },
			{ name = "scrollmask_v_lo" , index = 66, keepalive = 0x20000000, payload = 0x0001FFFE },
			{ name = "scrollmask_h_lo" , index = 67, keepalive = 0x20000000, payload = 0x0001FFFE },
			{ name = "scrollmask_v_hi" , index = 68, keepalive = 0x20000000, payload = 0x0001FFFE },
			{ name = "scrollmask_h_hi" , index = 69, keepalive = 0x20000000, payload = 0x0001FFFE },
			{ name = "forward_char"    , index = 70, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "char_data_hi_31" , index = 71, keepalive = 0x00000001, payload = 0xFFFFFFFE },
			{ name = "char_data_hi_1"  , index = 72, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "repeat_data"     , index = 73, keepalive = 0x20000000, payload = 0x1FFFFFFF },
			{ name = "char_data_lo_31" , index = 74, keepalive = 0x00000001, payload = 0xFFFFFFFE },
			{ name = "char_data_lo_1"  , index = 75, keepalive = 0x10000000, payload = 0x00000001 },
			{ name = "dray_enable_h"   , index = 76, keepalive = 0x10000004, payload = 0x00000001 },
			{ name = "dray_enable_v"   , index = 77, keepalive = 0x10000004, payload = 0x00000001 },
		},
		clobbers = { 57 },
		func = function(inputs)
			local hrange         = inputs.hrange
			local vrange         = inputs.vrange
			local cursor         = inputs.cursor
			local nlchar         = inputs.nlchar
			local color          = inputs.color
			local scrollmask_lo  = inputs.scrollmask_lo
			local scrollmask_hi  = inputs.scrollmask_hi
			local beginbitmap_lo = inputs.beginbitmap_lo
			local beginbitmap_hi = inputs.beginbitmap_hi

			local written_source, data_source, addr_source = spaghetti.select(
				inputs.repeat_data:band(0x10000):zeroable(),
				0x10000001, inputs.written:band(0x10000001),
				inputs.repeat_data:bor(0x10000000):band(0x1000FFFF), inputs.data_lo_addr_hi,
				spaghetti.rshiftk(inputs.repeat_data, 16):bor(0x10000000):bsub(0x8000):bsub(0x4000):bsub(0x2000), inputs.addr_lo
			)

			local data_lo        = data_source:band(0x1000FFFF)
			local addr           = spaghetti.rshiftk(addr_source:band(0x1000FFFF):bsub(0x8000):bsub(0x4000):bsub(0x2000), 2)
			local addr_written   = addr:bor(spaghetti.lshiftk(written_source:bxor(1):bor(0x100), 12))
			local repeat_data    = data_lo:bxor(0x30000000):bor(spaghetti.lshiftk(addr_source:bor(0x2000), 16)):bsub(0x10000)

			hrange = spaghetti.select(addr_written:bxor(1)        :band(0xFFFF):zeroable(), hrange, data_lo)
			vrange = spaghetti.select(addr_written:bxor(2)        :band(0xFFFF):zeroable(), vrange, data_lo)
			cursor = spaghetti.select(addr_written:bxor(3)        :band(0xFFFF):zeroable(), cursor, data_lo)
			nlchar = spaghetti.select(addr_written:bxor(4)        :band(0xFFFF):zeroable(), nlchar, data_lo)
			color  = spaghetti.select(addr_written:bxor(4):bxor(1):band(0xFFFF):zeroable(), color , data_lo:band(0x100000FF))
			scrollmask_lo, scrollmask_hi = spaghetti.select(
				addr_written:bxor(4):bxor(2):band(0xFFFF):zeroable(),
				scrollmask_lo, data_lo,
				scrollmask_hi, inputs.data_hi
			)
			beginbitmap_lo, beginbitmap_hi = spaghetti.select(
				spaghetti.rshiftk(addr_written, 8):bxor(1):band(0xFF):zeroable(), -- beginbitmap
				beginbitmap_lo, data_lo:bor(spaghetti.lshiftk(addr:bor(0x1000), 16)),
				beginbitmap_hi, inputs.data_hi
			)
			local cmem_writer = spaghetti.select(
				spaghetti.rshiftk(addr_written, 9):bxor(1):band(0xFF):zeroable(), -- cmem
				addr:bsub(0x200),
				addr:bor(0x200)
			)
			local pixel_plotter = spaghetti.lshiftk(data_lo:band(0x100000FF):bor(0x10000), 8):bor(spaghetti.rshiftk(data_lo, 8))
			local bank_color
			pixel_plotter, bank_color = spaghetti.select(
				addr_written:bxor(7):band(0xFFFF):zeroable(), -- plotpix
				pixel_plotter:bor(0x10000), pixel_plotter,
				0x10000000, inputs.data_hi:band(0x100000FF)
			)
			local char_data_hi_stack = stack_31_1.component({
				low_half  = data_lo,
				high_half = inputs.data_hi,
			})
			local char_data_lo_stack = stack_31_1.component({
				low_half  = inputs.beginbitmap_lo:band(0x1000FFFF),
				high_half = inputs.beginbitmap_hi,
			})

			local range_from_cursor, forward_char
			range_from_cursor, forward_char, bank_color = spaghetti.select(
				spaghetti.rshiftk(addr_written, 10):bxor(1):band(0xFF):zeroable(), -- endbitmap
				inputs.data_hi, addr:bor(0x10000000),
				0x10000000, 0x10000001,
				bank_color, spaghetti.rshiftk(beginbitmap_lo, 16):bor(0x10000000):band(0x100000FF)
			)

			local scrollprint_horiz = spaghetti.rshiftk(addr_written, 2)
			local scrollprint_srange, scrollprint_prange, scrollprint_cursor
			local old_cursor_p, old_cursor_s, overflow_scroll, repeat_scrollprint_early
			do
				local cursor_x = cursor
				local cursor_y = spaghetti.rshiftk(cursor, 5):bor(0x10000000)
				local cursor_s, cursor_p
				scrollprint_srange, scrollprint_prange, cursor_p, cursor_s = spaghetti.select(
					scrollprint_horiz:band(1):zeroable(),
					hrange, vrange,
					vrange, hrange,
					cursor_y, cursor_x,
					cursor_x, cursor_y
				)
				local prange_lo =                   scrollprint_prange
				local prange_hi = spaghetti.rshiftk(scrollprint_prange, 5)
				local srange_lo =                   scrollprint_srange
				local srange_hi = spaghetti.rshiftk(scrollprint_srange, 5)
				local function incr_cursor(expr, range_lo, range_hi)
					local range_lo_bigger
					do
						local diff = range_hi:bxor(range_lo):band(0x1000001F)
						local to_check = 1
						for i = 2, 0, -1 do
							local b = bitx.lshift(1, i)
							to_check = spaghetti.select(
								spaghetti.rshiftk(diff:rshift(to_check):never_zero(), b):never_zero():band(0xFFFF):zeroable(),
								spaghetti.lshiftk(to_check, b):never_zero(), to_check
							):never_zero()
						end
						range_lo_bigger = range_lo:band(diff):rshift(to_check):never_zero()
					end
					do
						local inv = expr
						inv = spaghetti.select(range_lo_bigger:band(1):zeroable(), inv, inv:bxor(0xFFFF))
						local flip = spaghetti.constant(0x3FFFFFFE):lshift(inv):never_zero():bxor(0xFFFF)
						expr = expr:bxor(flip:never_zero():bsub(0x10000000):never_zero())
					end
					return expr
				end
				local term_scroll = spaghetti.rshiftk(addr, 4)
				overflow_scroll = term_scroll
				local new_cursor_s = spaghetti.select(
					term_scroll:band(1):zeroable(),
					cursor_s, srange_lo
				)
				local cursor_s_incr
				cursor_s_incr, overflow_scroll = spaghetti.select(
					srange_hi:bxor(cursor_s):bsub(0x80):bsub(0x40):bsub(0x20):band(0xFF):zeroable(),
					incr_cursor(cursor_s, srange_lo, srange_hi), new_cursor_s,
					0x10000000, term_scroll:bor(0x10000000)
				)
				local nlchar_match = spaghetti.select(
					data_source:bxor(0x20000000):bxor(nlchar):bor(spaghetti.rshiftk(addr_written, 5):bxor(1):bsub(0xFFFE)):band(0xFF):zeroable(),
					0x10000000, 0x10000001
				)
				local prange_overflow = spaghetti.rshiftk(cursor, 12):bor(nlchar_match)
				repeat_scrollprint_early = spaghetti.rshiftk(cursor, 12):bsub(nlchar_match):bor(0x10000000):band(0x10000001)
				overflow_scroll = overflow_scroll:band(prange_overflow)
				cursor_p, cursor_s = spaghetti.select(
					prange_overflow:band(1):zeroable(),
					prange_lo, cursor_p,
					cursor_s_incr, cursor_s
				)
				old_cursor_p, old_cursor_s = cursor_p:band(0x1000001F), cursor_s:band(0x1000001F)
				local overflow = spaghetti.select(
					prange_hi:bxor(cursor_p):bsub(0x80):bsub(0x40):bsub(0x20):band(0xFF):zeroable(),
					0x10000000, 0x10000001
				)
				cursor_p = spaghetti.select(prange_overflow:band(1):zeroable(), cursor_p, incr_cursor(cursor_p, prange_lo, prange_hi))
				cursor_x, cursor_y = spaghetti.select(
					scrollprint_horiz:band(1):zeroable(),
					cursor_s, cursor_p,
					cursor_p, cursor_s
				)
				scrollprint_cursor = spaghetti.lshiftk(overflow:bor(0x10000), 12):bor(spaghetti.lshiftk(cursor_y:band(0x1000001F):bor(0x10000), 5)):bor(cursor_x:band(0x1000001F)):band(0x1000FFFF)
			end

			local scroll_enable = forward_char
			local horiz_scroll, scrollprint

			local scroll_color = spaghetti.select(
				spaghetti.rshiftk(addr, 1):band(1):zeroable(),
				spaghetti.rshiftk(data_lo, 8):bor(0x10000000),
				inputs.color
			)
			bank_color, scroll_enable, horiz_scroll, scrollprint = spaghetti.select(
				spaghetti.rshiftk(addr_written, 7):bxor(1):band(0xFF):zeroable(), -- scrollprint
				bank_color, scroll_color,
				scroll_enable, 0x10000001,
				0x10000000, scrollprint_horiz:bor(0x10000000):band(0x10000001),
				0x10000001, 0x10000000
			)

			local srange, prange
			do
				local rfc_x = range_from_cursor:band(0x1000001F)
				local rfc_y = spaghetti.rshiftk(range_from_cursor, 5):bor(0x10000000):band(0x1000001F)
				srange = rfc_y:bor(spaghetti.lshiftk(rfc_y:bor(0x10000), 5):bor(0x10000000):band(0x1000FFFF))
				prange = rfc_x:bor(spaghetti.lshiftk(rfc_x:bor(0x10000), 5):bor(0x10000000):band(0x1000FFFF))
			end

			scrollprint_srange, scrollprint_prange = spaghetti.select(
				addr:bsub(overflow_scroll):band(1):zeroable(), -- terminal mode
				old_cursor_s:bor(spaghetti.lshiftk(old_cursor_s:bor(0x10000), 5):bor(0x10000000):band(0x1000FFFF)), scrollprint_srange,
				old_cursor_p:bor(spaghetti.lshiftk(old_cursor_p:bor(0x10000), 5):bor(0x10000000):band(0x1000FFFF)), scrollprint_prange
			)
			srange, prange = spaghetti.select(
				scrollprint:bor(spaghetti.rshiftk(addr, 6)):band(1):zeroable(), -- scrollprint with position not from data
				srange, scrollprint_srange,
				prange, scrollprint_prange
			)
			local rewrite_char, repeat_scrollprint
			cursor, rewrite_char, repeat_scrollprint = spaghetti.select(
				scrollprint:bor(addr:bxor(0xFFFF)):band(1):zeroable(), -- scrollprint with terminal mode
				cursor, scrollprint_cursor,
				0x10000000, overflow_scroll,
				0x10000000, repeat_scrollprint_early
			)
			local use_scrollmask = scrollprint:bor(spaghetti.rshiftk(addr:bxor(0xFFFF), 3))

			local scrollmask_i_lo
			local scrollmask_i_hi
			do
				local function shift_mask(index)
					local shift_by = spaghetti.constant(1)
					for i = 0, 3 do
						local b = bitx.lshift(1, i)
						local bb = bitx.lshift(1, b)
						shift_by = shift_by:lshift(index:rshift(b):bsub(0xFFFE):bxor(1):bor(bb)):never_zero()
					end
					local lo = spaghetti.constant(0x1000FFFF):bor(spaghetti.constant(0x10000000):rshift(shift_by):never_zero()):lshift(shift_by):never_zero():band(0x1000FFFF):force(0x10000000, 0x0000FFFF)
					local hi = spaghetti.constant(0x1000FFFF)
					local shift_by_lo = shift_by:bor(0x10000000)
					local shift_by_hi = spaghetti.constant(0x10000000)
					lo, hi, shift_by_lo, shift_by_hi = spaghetti.select(
						index:band(0x10):zeroable(),
						spaghetti.constant(0x10000000), lo,
						lo, hi,
						spaghetti.constant(0x10000000), shift_by_lo,
						shift_by_lo, shift_by_hi
					)
					return lo, hi, shift_by_lo, shift_by_hi
				end
				local set_lo_begin, set_hi_begin, extra_lo_begin, extra_hi_begin = shift_mask(                  prange    )
				local set_lo_end  , set_hi_end  , extra_lo_end  , extra_hi_end   = shift_mask(spaghetti.rshiftk(prange, 5))
				scrollmask_i_lo = set_lo_begin:bxor(set_lo_end:bxor(0x30000000)):bxor(0x20000000):bor(extra_lo_begin):bor(extra_lo_end)
				scrollmask_i_hi = set_hi_begin:bxor(set_hi_end:bxor(0x30000000)):bxor(0x20000000):bor(extra_hi_begin):bor(extra_hi_end)
			end
			scrollmask_i_lo, scrollmask_i_hi = spaghetti.select(
				use_scrollmask:band(1):zeroable(),
				scrollmask_i_lo, scrollmask_lo,
				scrollmask_i_hi, scrollmask_hi
			)
			scrollmask_i_lo, scrollmask_i_hi = spaghetti.select(
				scroll_enable:band(1):zeroable(),
				scrollmask_i_lo, 0x10000000,
				scrollmask_i_hi, 0x10000000
			)
			local scrollmask_h_lo, scrollmask_h_hi, dray_enable_h, scrollmask_v_lo, scrollmask_v_hi, dray_enable_v = spaghetti.select(
				horiz_scroll:band(1):zeroable(),
				scrollmask_i_lo, 0x10000000,
				scrollmask_i_hi, 0x10000000,
				scroll_enable, 0x10000000,
				0x10000000, scrollmask_i_lo,
				0x10000000, scrollmask_i_hi,
				0x10000000, scroll_enable
			)
			local bank_select = bank_color:bor(spaghetti.lshiftk(                  srange                    :band(0x1000001F):bor(0x1000), 15))
			                              :bor(spaghetti.lshiftk(spaghetti.rshiftk(srange, 5):bor(0x10000000):band(0x1000001F):bor(0x1000),  9))
			                              :bor(spaghetti.lshiftk(horiz_scroll:bor(0x1000),  8))
			                              :bor(spaghetti.lshiftk(horiz_scroll:bor(0x1000), 14))

			local char_index = spaghetti.select(rewrite_char:band(1):zeroable(), nlchar, data_source)
			local char_select_c = char_index:band(0x100000FF):bsub(0x80):bsub(0x40)
			local char_select_r = spaghetti.rshiftk(char_index:band(0x100000FF), 6):bor(0x10000000):band(0x1000FFFF)
			local char_select_c_8  = comp_common.incr16(char_select_c  , 3, false, 7):band(0x100000FF)
			local char_select_c_12 = comp_common.incr16(char_select_c_8, 2, false, 7):band(0x100000FF)
			local char_select_r_8  = char_select_r:bor(8)
			return {
				hrange           = hrange,
				vrange           = vrange,
				cursor           = cursor,
				nlchar           = nlchar,
				color            = color,
				scrollmask_lo    = scrollmask_lo,
				scrollmask_hi    = scrollmask_hi,
				beginbitmap_lo   = beginbitmap_lo,
				beginbitmap_hi   = beginbitmap_hi,
				cmem_writer      = cmem_writer,
				pixel_plotter    = spaghetti.lshiftk(pixel_plotter, 1),
				bank_select      = bank_select,
				char_data_hi_31  = char_data_hi_stack.both_31,
				char_data_hi_1   = char_data_hi_stack.both_1,
				char_data_lo_31  = char_data_lo_stack.both_31,
				char_data_lo_1   = char_data_lo_stack.both_1,
				char_select_c_12 = char_select_c_12,
				char_select_c_8  = char_select_c_8,
				char_select_r_8  = char_select_r_8,
				scrollmask_h_lo  = spaghetti.lshiftk(scrollmask_h_lo, 1),
				scrollmask_h_hi  = spaghetti.lshiftk(scrollmask_h_hi, 1),
				scrollmask_v_lo  = spaghetti.lshiftk(scrollmask_v_lo, 1),
				scrollmask_v_hi  = spaghetti.lshiftk(scrollmask_v_hi, 1),
				forward_char     = forward_char,
				repeat_data      = repeat_data:bor(spaghetti.lshiftk(repeat_scrollprint:bor(0x2000), 16)),
				dray_enable_h    = dray_enable_h:bxor(4):bxor(1),
				dray_enable_v    = dray_enable_v:bxor(4):bxor(1),
			}
		end,
		fuzz_inputs = function()
			local nlchar          = math.random(0, 0x0000FFFF)
			local data_lo_addr_hi = bitx.bor(0x10000000, math.random(0, 0x07FFFFFF))
			if math.random(1, 100) == 1 then
				nlchar = bitx.bor(bitx.band(nlchar, 0xFFFFFF00), bitx.band(data_lo_addr_hi, 0xFF))
			end
			return {
				hrange          = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				vrange          = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				cursor          = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				nlchar          = bitx.bor(0x10000000, nlchar),
				color           = bitx.bor(0x10000000, math.random(0, 0x000000FF)),
				scrollmask_lo   = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				scrollmask_hi   = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				-- written         = bitx.bor(0x10000000, math.random(3, 4)),
				-- addr_lo         = bitx.bor(0x10000000, bitx.lshift(math.random(0, 0x00FFFFFF), 2)),
				written         = 0x10000003,
				addr_lo         = 0x1000001C,
				data_lo_addr_hi = data_lo_addr_hi,
				data_hi         = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				beginbitmap_lo  = bitx.bor(0x10000000, math.random(0, 0x07FFFFFF)),
				beginbitmap_hi  = bitx.bor(0x10000000, math.random(0, 0x0000FFFF)),
				repeat_data     = bitx.bor(0x22000000, math.random(0, 0xFFFF), bitx.lshift(math.random(0, 0x7F), 18), math.random(0, 99) == 0 and 0x10000 or 0),
			}
		end,
		fuzz_outputs = function(inputs)
			local written        = bitx.band(inputs.written, 1) ~= 0
			local addr           = bitx.band(inputs.addr_lo        , 0x1FFF)
			local data_lo        = bitx.band(inputs.data_lo_addr_hi, 0xFFFF)
			local data_hi        = bitx.band(inputs.data_hi        , 0xFFFF)
			local hrange         = bitx.band(inputs.hrange         , 0xFFFF)
			local vrange         = bitx.band(inputs.vrange         , 0xFFFF)
			local cursor         = bitx.band(inputs.cursor         , 0xFFFF)
			local nlchar         = bitx.band(inputs.nlchar         , 0xFFFF)
			local color          = bitx.band(inputs.color          , 0xFF)
			local scrollmask_lo  = bitx.band(inputs.scrollmask_lo  , 0xFFFF)
			local scrollmask_hi  = bitx.band(inputs.scrollmask_hi  , 0xFFFF)
			local beginbitmap_lo = bitx.band(inputs.beginbitmap_lo , 0xFFFFFF)
			local beginbitmap_hi = bitx.band(inputs.beginbitmap_hi , 0xFFFF)

			if bitx.band(inputs.repeat_data, 0x10000) ~= 0 then
				written = true
				addr    = bitx.band(bitx.rshift(inputs.repeat_data, 16), 0x1FFF)
				data_lo = bitx.band(inputs.repeat_data, 0xFFFF)
			end

			local pixel_plotter  = bitx.bor(0x10000, bitx.rshift(data_lo, 8), bitx.lshift(bitx.band(data_lo, 0xFF), 8))
			local char_data_lo   = common.merge32(bitx.band(beginbitmap_lo, 0xFFFF), bitx.band(beginbitmap_hi, 0xFFFF))
			local char_data_hi   = common.merge32(data_lo, data_hi)
			local cmem_writer    = bitx.band(bitx.rshift(addr, 2), 0x1FF)
			local repeat_data    = bitx.band(bitx.bor(bitx.lshift(addr, 16), data_lo), 0xFFFEFFFF)
			local char_index     = bitx.band(data_lo, 0xFF)

			local bank_color = 0
			local bank_begin = 0
			local bank_end   = 0

			local function range_from_cursor_x(expr)
				local x = bitx.band(expr, 0x1F)
				return bitx.bor(x, bitx.lshift(x, 5))
			end
			local function range_from_cursor_y(expr)
				local y = bitx.band(bitx.rshift(expr, 5), 0x1F)
				return bitx.bor(y, bitx.lshift(y, 5))
			end
			local prange = 0
			local srange = 0
			local check_bank_select = 0x10000000
			local horiz_scroll = false
			local forward_char = false
			local scroll_enable = false
			local use_scrollmask = false

			local repeat_scrollprint = false
			if written then
				if addr == 0x04 then hrange = data_lo end
				if addr == 0x08 then vrange = data_lo end
				if addr == 0x0C then cursor = data_lo end
				if addr == 0x10 then nlchar = data_lo end
				if addr == 0x14 then color  = bitx.band(data_lo, 0xFF) end
				if addr == 0x18 then
					scrollmask_lo = data_lo
					scrollmask_hi = data_hi
				end
				if addr == 0x1C then -- plotpix
					pixel_plotter = bitx.bxor(pixel_plotter, 0x10000)
					bank_color = bitx.band(data_hi, 0xFF)
					check_bank_select = 0x100000FF
				end
				if bitx.band(addr, 0x1E00) == 0x0200 then -- scrollprint
					if bitx.band(addr, 0x10) ~= 0 then
						horiz_scroll = true
					end
					local scrollprint_prange = horiz_scroll and vrange or hrange
					local scrollprint_srange = horiz_scroll and hrange or vrange
					local use_ranges = true
					if bitx.band(addr, 0x4) ~= 0 then
						use_ranges = false
						local cursor_x = bitx.band(            cursor    , 0x1F)
						local cursor_y = bitx.band(bitx.rshift(cursor, 5), 0x1F)
						local cursor_p = horiz_scroll and cursor_y or cursor_x
						local cursor_s = horiz_scroll and cursor_x or cursor_y
						local prange_lo = bitx.band(            scrollprint_prange    , 0x1F)
						local prange_hi = bitx.band(bitx.rshift(scrollprint_prange, 5), 0x1F)
						local srange_lo = bitx.band(            scrollprint_srange    , 0x1F)
						local srange_hi = bitx.band(bitx.rshift(scrollprint_srange, 5), 0x1F)
						local newline_trigger = bitx.band(addr, 0x80) ~= 0 and bitx.band(nlchar, 0xFF) == char_index
						local prev_overflow = bitx.band(cursor, 0x1000) ~= 0
						if prev_overflow or newline_trigger then
							cursor_p = prange_lo
							if cursor_s == srange_hi then
								if bitx.band(addr, 0x40) ~= 0 then
									use_ranges = true
									char_index = bitx.band(nlchar, 0xFF)
								else
									cursor_s = srange_lo
								end
							else
								cursor_s = (cursor_s + ((srange_lo <= srange_hi) and 1 or -1)) % 0x20
							end
						end
						if prev_overflow and not newline_trigger then
							repeat_scrollprint = true
						end
						prange = bitx.bor(cursor_p, bitx.lshift(cursor_p, 5))
						srange = bitx.bor(cursor_s, bitx.lshift(cursor_s, 5))
						local overflow = (cursor_p == prange_hi) and 1 or 0
						if not prev_overflow and not newline_trigger then
							cursor_p = (cursor_p + ((prange_lo <= prange_hi) and 1 or -1)) % 0x20
						end
						cursor_x = horiz_scroll and cursor_s or cursor_p
						cursor_y = horiz_scroll and cursor_p or cursor_s
						cursor = bitx.bor(bitx.lshift(overflow, 12), bitx.lshift(cursor_y, 5), cursor_x)
					end
					if use_ranges then
						prange = scrollprint_prange
						srange = scrollprint_srange
					end
					if bitx.band(addr, 0x100) ~= 0 then
						local data_cursor = bitx.band(data_hi, 0x3FF)
						prange = range_from_cursor_x(data_cursor)
						srange = range_from_cursor_y(data_cursor)
					end
					if bitx.band(addr, 0x20) ~= 0 then
						use_scrollmask = true
					end
					if bitx.band(addr, 0x8) ~= 0 then
						bank_color = bitx.rshift(data_lo, 8)
					else
						bank_color = color
					end
					scroll_enable = true
					check_bank_select = 0x100FFFFF
				end
				if bitx.band(addr, 0x1C00) == 0x0400 then -- beginbitmap
					beginbitmap_lo = bitx.bor(data_lo, bitx.lshift(bitx.band(bitx.rshift(addr, 2), 0xFF), 16))
					beginbitmap_hi = data_hi
				end
				if bitx.band(addr, 0x1800) == 0x0800 then -- cmem
					cmem_writer = bitx.bor(cmem_writer, 0x200)
				end
				if bitx.band(addr, 0x1000) == 0x1000 then -- endbitmap
					local data_cursor = bitx.band(bitx.rshift(addr, 2), 0x3FF)
					prange = range_from_cursor_x(data_cursor)
					srange = range_from_cursor_y(data_cursor)
					check_bank_select = 0x100FFFFF
					forward_char = true
					scroll_enable = true
					bank_color = bitx.band(bitx.rshift(beginbitmap_lo, 16), 0xFF)
				end
			end

			local scrollmask_i
			do
				local function shift_mask(index)
					if index == 32 then
						return 0
					end
					return bitx.lshift(0xFFFFFFFF, index)
				end
				local scroll_begin = bitx.band(            prange    , 0x1F)
				local scroll_end   = bitx.band(bitx.rshift(prange, 5), 0x1F)
				if scroll_begin > scroll_end then
					scroll_begin, scroll_end = scroll_end, scroll_begin
				end
				scrollmask_i = bitx.bxor(shift_mask(scroll_begin), shift_mask(scroll_end + 1))
			end
			if use_scrollmask then
				scrollmask_i = common.merge32(scrollmask_lo, scrollmask_hi)
			end

			local hl_adjust = horiz_scroll and 1 or 0
			local bank_select = bitx.bor(
				                                  bank_color,
				bitx.lshift(                      hl_adjust            ,  8),
				bitx.lshift(bitx.band(            srange        , 0x1F), 15),
				bitx.lshift(                      hl_adjust            , 14),
				bitx.lshift(bitx.band(bitx.rshift(srange    , 5), 0x1F),  9)
			)
			local scrollmask_i_lo, scrollmask_i_hi = common.split32(scrollmask_i)
			return {
				hrange           = bitx.bor(0x10000000, hrange        ),
				vrange           = bitx.bor(0x10000000, vrange        ),
				cursor           = bitx.bor(0x10000000, cursor        ),
				nlchar           = bitx.bor(0x10000000, nlchar        ),
				color            = bitx.bor(0x10000000, color         ),
				scrollmask_lo    = bitx.bor(0x10000000, scrollmask_lo ),
				scrollmask_hi    = bitx.bor(0x10000000, scrollmask_hi ),
				beginbitmap_lo   = { value = bitx.bor(0x10000000, beginbitmap_lo), mask = 0x10FFFFFF },
				beginbitmap_hi   = bitx.bor(0x10000000, beginbitmap_hi),
				cmem_writer      = { value = bitx.bor(0x04000000, cmem_writer), mask = 0x040003FF },
				pixel_plotter    = bitx.lshift(bitx.bor(0x01100000, pixel_plotter ), 1),
				bank_select      = { value = bitx.bor(0x1C300000, bank_select), mask = check_bank_select },
				char_data_lo_31  = bitx.bor(char_data_lo, 1),
				char_data_lo_1   = bitx.bor(0x10000000, bitx.band(char_data_lo, 1)),
				char_data_hi_31  = bitx.bor(char_data_hi, 1),
				char_data_hi_1   = bitx.bor(0x10000000, bitx.band(char_data_hi, 1)),
				char_select_c_12 = bitx.bor(0x10000000, 12 + bitx.band(char_index, 0x3F)),
				char_select_c_8  = bitx.bor(0x10000000, 8  + bitx.band(char_index, 0x3F)),
				char_select_r_8  = bitx.bor(0x10000000, 8  + bitx.rshift(char_index, 6)),
				scrollmask_h_lo  = bitx.lshift(bitx.bor(0x10000000, (    horiz_scroll and scroll_enable) and scrollmask_i_lo or 0), 1),
				scrollmask_h_hi  = bitx.lshift(bitx.bor(0x10000000, (    horiz_scroll and scroll_enable) and scrollmask_i_hi or 0), 1),
				dray_enable_h    = bitx.bxor(0x10000005, (    horiz_scroll and scroll_enable) and 1 or 0),
				scrollmask_v_lo  = bitx.lshift(bitx.bor(0x10000000, (not horiz_scroll and scroll_enable) and scrollmask_i_lo or 0), 1),
				scrollmask_v_hi  = bitx.lshift(bitx.bor(0x10000000, (not horiz_scroll and scroll_enable) and scrollmask_i_hi or 0), 1),
				dray_enable_v    = bitx.bxor(0x10000005, (not horiz_scroll and scroll_enable) and 1 or 0),
				forward_char     = bitx.bor(0x10000000, forward_char and 1 or 0),
				repeat_data      = bitx.bor(0x20000000, repeat_data, repeat_scrollprint and 0x10000 or 0),
			}
		end,
	}
end)
