# Building the examples in this directory

- get [Meson](https://mesonbuild.com/)
- get GCC or a compatible toolchain for riscv32 that supports bare-metal hardware
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
- upload the resulting binary, e.g. `Echo.bin`, to an R4 (TODO: how?)

# Adding new programs the lazy way

- find the part in [meson.build](./meson.build) that lists examples:
```meson
foreach example : [
	'Echo',
	...
```
- add your own at the end of the list, e.g. `Doom`
- create a `Doom` directory
- create `Doom/Main.cpp` and put your code in it
- create `Doom/Hardware.ld` and list the peripherals in it specific to your demo (see other per-demo linker scripts in this directory for inspiration)
- optionally create `Doom/Hardware.hpp`, include it in `Doom/Main.cpp`, keep it in sync with `Doom/Hardware.ld` (TODO: generate `Hardware.*` with r4plot)
