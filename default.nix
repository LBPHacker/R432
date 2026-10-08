{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    lua5_1
    luajit

    # RISC-V bare-metal toolchain
    pkgsCross.riscv32-embedded.stdenv.cc

    # spaghetti
    stdenv.cc
    meson
    pkg-config
    cmake
    cryptominisat
    ninja
  ];
}
