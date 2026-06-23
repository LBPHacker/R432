# Building the examples in this directory

- get [Meson](https://mesonbuild.com/)
- get GCC or a compatible toolchain for riscv32 that supports bare-metal hardware
  - [prebuilt toolchain](https://xpack-dev-tools.github.io/riscv-none-elf-gcc-xpack/docs/install/#manual-installation) for Windows
  - `riscv32-gnu-toolchain-elf-bin` on [AUR](https://aur.archlinux.org/)
- adjust [toolchain.ini](./toolchain.ini) to reflect the properties of this toolchain
- set up a build site with e.g.
```sh
meson setup --cross-file=toolchain.ini -Dbuildtype=debugoptimized build
```
- build with
```sh
cd build
meson compile
```
- upload the resulting binary, e.g. `"/absolute/path/to/Echo.bin"`, to an R4 through the [`.memory` property](../manual.md#memory-property) of the computer's configuration

# Adding new programs the lazy way

- find the part in [meson.build](./meson.build) that lists examples:
```meson
foreach example : [
	'Echo',
	...
```
- add your own at the end of the list, e.g. `Doom`
- create a `Doom` directory in `Programs`
- create `Programs/Doom/Main.cpp` and put your code in it
- create `Programs/Doom/Hardware.ld` and list the peripherals in it specific to your demo (see other per-demo linker scripts in this directory for inspiration)
- optionally create `Programs/Doom/Hardware.hpp`, include it in `Programs/Doom/Main.cpp`, keep it in sync with `Programs/Doom/Hardware.ld`
