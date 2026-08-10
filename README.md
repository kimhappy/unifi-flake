# unifi-flake

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    unifi-flake = {
      url = "github:kimhappy/unifi-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, unifi-flake, ... }: {
    nixosConfigurations.mymachine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        unifi-flake.nixosModules.default
        {
          networking.networkmanager.enable = true;

          # The package repackages Ubiquiti's proprietary .deb and is marked
          # unfree, so it will not evaluate without this.
          nixpkgs.config.allowUnfree = true;

          services.unifi-endpoint = {
            enable = true;
            users = [ "alice" ];
          };
        }
      ];
    };
  };
}
```
