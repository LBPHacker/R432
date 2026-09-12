# Setup

## nix (linux)

```bash
nix-shell
```

## Other

install [rustup](https://rust-lang.org/tools/install/)

run 
```shell
rustup toolchain install stable --profile minimal
rustup target add riscv32i-unknown-none-elf --toolchain stable
rustup component add llvm-tools --toolchain stable
cargo install cargo-binutils
```

# Building

> [!NOTE]
> When building you will get a warning for an unknown feature. This is fine

```shell
./build.sh
```

# Making your own.

Clone this directory

To change name edit 

`build.sh`
```bash
NAME="<name>"
```
`Cargo.toml`
```toml
name = "<name>"
```
they *must* match

hardware defined in `config.lua` must manually be synced with `hardware.ld`, and `mmio/mod.rs` must have the correct types / link names to reflect `hardware.ld`

# Loading

edit `config.lua` (the config this demo expects) and replace `<BIN PATH>` with the abs path printed by the build script, and `/path/to/r4plot.lua` to the abs path of the `r4plot.lua` file. Paste the result into TPT console 