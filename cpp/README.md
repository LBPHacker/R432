# Building the showcase

- get [Meson](https://mesonbuild.com/)
- get GCC or a compatible toolchain for riscv32 that supports bare-metal hardware
  - [prebuilt toolchain](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/docs/install/#manual-installation) for Windows
  - `riscv32-gnu-toolchain-elf-bin` on [AUR](https://aur.archlinux.org/)
- adjust [toolchain.ini](./toolchain.ini) to reflect the properties of this toolchain
- set up a build site with e.g.
```sh
meson setup --cross-file=toolchain.ini -Dbuildtype=debugoptimized build-release
```
- build with
```sh
cd build
meson compile
```
- upload the resulting binary, e.g. `"/absolute/path/to/Showcase.bin"`, to an R4 through the [`.memory` property](../manual.md#memory-property) of the computer's configuration

# Making your own programs the lazy way

- clone this directory
- replace `Showcase` with your choice in [meson.build](./meson.build), e.g. `Doom`
```meson
project(
	'Doom',
	...
```
- make sure that you keep the contents of [Hardware.ld](./Hardware.ld), [Hardware.hpp](./Hardware.hpp), and your *r4plot.lua* invocation in sync
	- the addresses in the *r4plot.lua* invocation and Hardware.ld must match
	- the symbol names in the Hardware.hpp invocation and Hardware.ld must match
	- (it should be really easy to generate Hardware.hpp and Hardware.ld from the *r4plot.lua* invocation, maybe I'll look into this later...)
- build as above
- upload the resulting binary, which will now be named `Doom.bin`
