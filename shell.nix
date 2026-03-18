{ pkgs ? import <nixpkgs> {} }:

let
  plenary = pkgs.vimPlugins.plenary-nvim;
in

pkgs.mkShell {
  buildInputs = with pkgs; [
    (neovim.override { })
    stylua
    git
    plenary
  ];

  PLENARY_PATH = plenary.outPath;
}
