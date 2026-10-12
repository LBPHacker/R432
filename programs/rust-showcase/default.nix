{ pkgs ? import <nixpkgs> {} }:
pkgs.mkShell {
  packages = with pkgs; [
    rustup
    cargo-binutils
  ];


  shellHook = ''
    rustup toolchain install stable --profile minimal
    rustup target add riscv32i-unknown-none-elf --toolchain stable
    rustup component add llvm-tools --toolchain stable
  '';
}
