{
  description = "Custom Linux kernel build";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          crossSystem = {
            config = "aarch64-unknown-linux-gnu";
            system = "aarch64-linux";
          };
        };
      in
      {
        packages = let
          kernels = pkgs.callPackage ./kernel.nix { };
          rootfs = pkgs.callPackage ./rootfs.nix {
            linux-gpuvm = kernels.linux-gpuvm;
          };
        in rec {
          linux-gpuvm = kernels.linux-gpuvm;
          ubuntu-rootfs = rootfs;
          default = linux-gpuvm;
        };

        overlay = final: prev: {
          linux = self.packages.${system}.linux-gpuvm;
        };
      }
    ) // {
      nixosModule = { config, ... }: {
        nixpkgs.overlays = [ self.overlay ];
      };
    };
}
