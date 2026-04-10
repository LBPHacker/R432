project(
	'echo',
	[ 'c', 'cpp' ],
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

objcopy = find_program('objcopy')
foreach example : [
	'Echo',
	'Primes',
]
	custom_target(
		'@0@.bin'.format(example),
		build_by_default: true,
		command: [
			objcopy,
			'@INPUT@',
			'-O',
			'binary',
			'@OUTPUT@',
		],
		input: executable(
			'@0@.elf'.format(example),
			sources: [
				'Start.S',
				'Runtime.c',
				'@0@/Main.cpp'.format(example),
			],
			c_args: c_args,
			cpp_args: cpp_args,
			include_directories: include_directories('.'),
			link_depends: [
				'common.ld',
				'@0@/Hardware.ld'.format(example),
			],
			link_args: [
				'-T', meson.current_source_dir() / 'common.ld',
				'-T', meson.current_source_dir() / '@0@/Hardware.ld'.format(example),
				'-Wl,--gc-sections',
				'-Wl,--no-warn-rwx-segments',
			] + cpp_args,
		),
		output: '@0@.bin'.format(example),
	)
endforeach
