{
  description = "nilm env";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, home-manager }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      this-py = pkgs.python310;
      py-deps = ps: with ps; [
        pandas
        pytorch
        scikit-learn
        tensorboard
        tqdm
      ];
      deps = with pkgs; [
        bash
        coreutils

        (this-py.withPackages py-deps)
      ];
    in {
      devShells.default = pkgs.mkShell rec {
        packages = deps;
      };
      packages.docker = pkgs.dockerTools.buildImage {
        name = "python-nix";
        config = {
          Cmd = [ "python3" "inference.py" ];
          WorkingDir = "/";
        };
        copyToRoot = pkgs.buildEnv {
          name = "image-root";
          paths = [ ./. ] ++ deps;
          pathsToLink = [ "/" ];
        };
      };
      packages.nixosConfigurations.myvm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          (nixpkgs + "/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix")
          ({ ... }:
          let
            files = pkgs.stdenv.mkDerivation {
              name = "project_files";
              src = ./.;
              phases = [ "installPhase" ];
              installPhase = ''
                mkdir -p $out
                cp -r $src $out
              '';
            };
          in
          {
            services.xserver.enable = true;
            networking.wireless.enable = false;

            # Enable the GNOME Desktop Environment.
            services.xserver.desktopManager.gnome.enable = true;
            services.xserver.displayManager = {
              gdm.enable = true;
              autoLogin = {
                enable = true;
                user = "alice";
              };
            };

            # Define a user account. Don't forget to set a password with ‘passwd’.
            users.users.alice = {
              isNormalUser = true;
              password = "alice";
              extraGroups = ["wheel"];
              packages = deps;
            };

            virtualisation.vmVariant = {
              # following configuration is added only when building VM with build-vm
              virtualisation = {
                memorySize = 10000;  # in MiB
                cores = 4;
              };
            };

            systemd.services.foo = {
              enable = true;
              description = "bar";
              unitConfig = {
                Type = "simple";
              };
              serviceConfig = {
                Type = "oneshot";
                User = "alice";
              };
              script = ''
                ${pkgs.coreutils}/bin/rm -rf /home/alice/PROJECT
                ${pkgs.coreutils}/bin/mkdir -p /home/alice/PROJECT
                ${pkgs.coreutils}/bin/cp -r ${files}/* /home/alice/PROJECT
                ${pkgs.coreutils}/bin/chown -R alice:alice PROJECT;
                ${pkgs.coreutils}/bin/chmod -R a+w PROJECT'';
              wantedBy = [ "multi-user.target" ];
            };

            system.stateVersion = "23.05";
          })

        ];
      };
    });
}
