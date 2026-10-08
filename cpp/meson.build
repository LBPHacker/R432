project(
	'Showcase',
	[ 'c', 'cpp' ],
	version: '0.0.1',
	default_options: [
		'c_std=c11',
		'cpp_std=c++20',
		'warning_level=3',
	],
	meson_version: '>=1.1',
)
c_args = [
	'-march=rv32i_zicond_zmmul_zifencei',
	'-mabi=ilp32',
	'-mbranch-cost=3',
	'-nostdlib',
	'-nostartfiles',
	'-ffreestanding',
	'-ffunction-sections',
	'-fdata-sections',
	'-fno-zero-initialized-in-bss',
]
cpp_args = c_args + [
	'-fno-rtti',
	'-fno-exceptions',
]

name = meson.project_name()
common_ld = 'Common.ld'
hardware_ld = 'Hardware.ld'
custom_target(
	'@0@.bin'.format(name),
	build_by_default: true,
	command: [
		find_program('objcopy'),
		'@INPUT@',
		'-O',
		'binary',
		'@OUTPUT@',
	],
	input: executable(
		'@0@.elf'.format(name),
		sources: [
			'Demos/Echo.cpp',
			'Demos/RandomSource.cpp',
			'Demos/FrameClock.cpp',
			'Demos/FiltRelay.cpp',
			'Demos/InstRelay.cpp',
			'Main.cpp',
			'Menu.cpp',
			'Print.cpp',
			'Time.cpp',
			'Start.S',
		],
		c_args: c_args,
		cpp_args: cpp_args,
		include_directories: include_directories([
			'Hardware',
		]),
		link_depends: [
			common_ld,
			hardware_ld,
		],
		link_args: [
			'-T', meson.current_source_dir() / common_ld,
			'-T', meson.current_source_dir() / hardware_ld,
			'-Wl,--gc-sections',
			'-Wl,--no-warn-rwx-segments',
		] + cpp_args,
	),
	output: '@0@.bin'.format(name),
)
