{
  description = "A Neovim plugin for opening Visual Studio Code .code-workspace multi-root workspace files.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      perSystem = {
        pkgs,
        system,
        ...
      }: {
        packages.default = pkgs.vimUtils.buildVimPlugin {
          pname = "code-workspace-nvim";
          version = "unstable";
          src = self;
          dependencies = [pkgs.vimPlugins.snacks-nvim];
        };
      };
    };
}
