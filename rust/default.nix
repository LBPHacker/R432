{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    rustup

    # RISC-V bare-metal toolchain
    pkgsCross.riscv32-embedded.stdenv.cc

    stdenv.cc
  ];

  shellHook = ''
    rustup toolchain install stable --profile minimal
    rustup target add riscv32i-unknown-none-elf

    export CARGO_BUILD_TARGET=riscv32i-unknown-none-elf
  '';
}
