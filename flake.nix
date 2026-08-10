{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    {
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          cfg = config.services.unifi-endpoint;

          fhsDir = "/usr/lib/UniFi-Endpoint";

          hookDir = "/run/unifi-endpoint-hooks";

          runtimeLibs = with pkgs; [
            glibc
            gcc-unwrapped.lib
            icu
            openssl
            zlib
            krb5
            fontconfig
            freetype
            glib
            gtk3
            gdk-pixbuf
            pango
            cairo
            libsecret
            libnotify
            libglvnd
            vulkan-loader
            libx11
            libxcursor
            libxext
            libxi
            libxrandr
            libxrender
            libxfixes
            libice
            libsm
          ];

          helperPath = lib.makeBinPath (
            with pkgs;
            [
              wireguard-tools
              iproute2
              networkmanager
              coreutils
              getent
            ]
          );

          appPath = lib.makeBinPath (
            with pkgs;
            [
              coreutils
              networkmanager
              wireguard-tools
              libsecret
              xdg-utils
              libnotify
            ]
          );

          pkg = pkgs.stdenv.mkDerivation {
            pname = "unifi-endpoint";
            version = "1.0.4-20";

            src = ./bed2-linux-1.0.4-20-ff164d14-a211-419d-9a04-43192d56a952.deb;

            nativeBuildInputs = with pkgs; [
              dpkg
              patchelf
              makeBinaryWrapper
            ];

            dontStrip = true;
            dontPatchELF = true;

            unpackPhase = ''
              runHook preUnpack
              dpkg-deb -x "$src" ./deb
              runHook postUnpack
            '';

            installPhase = ''
              runHook preInstall

              mkdir -p "$out/lib" "$out/bin" "$out/share"
              cp -r ./deb/usr/lib/UniFi-Endpoint "$out/lib/UniFi-Endpoint"
              chmod -R u+w "$out/lib/UniFi-Endpoint"

              cp -r ./deb/usr/share/icons "$out/share/icons"
              install -Dm644 ./deb/usr/share/polkit-1/actions/com.ui.unifi-endpoint.policy \
                "$out/share/polkit-1/actions/com.ui.unifi-endpoint.policy"
              install -Dm644 ./deb/usr/share/doc/unifi-endpoint/README.Debian \
                "$out/share/doc/unifi-endpoint/README.Debian"

              install -Dm644 ./deb/etc/polkit-1/rules.d/50-unifi-endpoint.rules \
                "$out/share/unifi-endpoint/50-unifi-endpoint.rules"
              install -Dm644 ./deb/etc/NetworkManager/conf.d/90-unifi-endpoint-unmanaged-vpn.conf \
                "$out/share/unifi-endpoint/90-unifi-endpoint-unmanaged-vpn.conf"

              runHook postInstall
            '';

            postFixup = ''
              libdir="$out/lib/UniFi-Endpoint"
              rpath="\$ORIGIN:${lib.makeLibraryPath runtimeLibs}"

              for exe in UIDSTD.Avalonia UniFi-Endpoint-Daemon UniFi-Endpoint-PrivilegedHelper; do
                patchelf \
                  --set-interpreter "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" \
                  --set-rpath "$rpath" \
                  "$libdir/$exe"
              done

              patchelf --set-interpreter "${pkgs.glibc}/lib/ld-linux-x86-64.so.2" "$libdir/utunnel"

              for so in libSkiaSharp.so libHarfBuzzSharp.so libsodium.so; do
                patchelf --set-rpath "$rpath" "$libdir/$so"
              done

              mv "$libdir/UniFi-Endpoint-PrivilegedHelper" \
                 "$libdir/.UniFi-Endpoint-PrivilegedHelper-real"
              makeWrapper "$libdir/.UniFi-Endpoint-PrivilegedHelper-real" \
                "$libdir/UniFi-Endpoint-PrivilegedHelper" \
                --set PATH "${hookDir}:${helperPath}"

              cat > "$out/bin/unifi-endpoint" <<EOF
              #!${pkgs.stdenv.shell}
              export PATH="\''${PATH:+\$PATH:}${appPath}"
              export GIO_EXTRA_MODULES="\''${GIO_EXTRA_MODULES:+\$GIO_EXTRA_MODULES:}${pkgs.glib-networking}/lib/gio/modules"
              exec ${fhsDir}/UIDSTD.Avalonia "\$@"
              EOF
              chmod +x "$out/bin/unifi-endpoint"

              install -Dm644 /dev/stdin "$out/share/applications/unifi-endpoint.desktop" <<EOF
              [Desktop Entry]
              Type=Application
              Version=1.5
              Name=UniFi Endpoint
              Comment=UniFi network access client - WiFi, VPN, and drive integration
              GenericName=Network Access Client
              Exec=$out/bin/unifi-endpoint %u
              TryExec=$out/bin/unifi-endpoint
              Icon=unifi-endpoint
              Terminal=false
              Categories=Network;Security;Utility;
              MimeType=x-scheme-handler/identity-standard;
              StartupNotify=true
              StartupWMClass=UIDSTD.Avalonia
              Keywords=UniFi;Ubiquiti;Endpoint;VPN;WiFi;
              EOF
            '';

            meta = {
              description = "UniFi network access client - WiFi, VPN, and drive integration";
              homepage = "https://ui.com/";
              license = {
                shortName = "ubiquiti-eula";
                fullName = "Ubiquiti End User License Agreement";
                url = "https://www.ui.com/legal/eula/";
                free = false;
                redistributable = false;
              };
              sourceProvenance = [ pkgs.lib.sourceTypes.binaryNativeCode ];
              platforms = [ "x86_64-linux" ];
              mainProgram = "unifi-endpoint";
            };
          };

          anchorDir = "/usr/local/share/ca-certificates";

          trustDir = "/var/lib/unifi-endpoint/trust";
          runtimeBundle = "${trustDir}/ca-certificates.crt";

          rebuildTrustStore = pkgs.writeShellApplication {
            name = "unifi-endpoint-update-ca-certificates";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              umask 022
              mkdir -p "${trustDir}" "${anchorDir}"
              tmp="${runtimeBundle}.tmp.$$"
              trap 'rm -f "$tmp"' EXIT
              cat "${config.security.pki.caBundle}" > "$tmp"
              for f in "${anchorDir}"/*.crt "${anchorDir}"/*.pem; do
                [ -e "$f" ] || continue
                printf '\n' >> "$tmp"
                cat "$f" >> "$tmp"
              done
              [ -s "$tmp" ]
              chmod 0644 "$tmp"
              mv -f "$tmp" "${runtimeBundle}"
            '';
          };
        in
        {
          options.services.unifi-endpoint = {
            enable = lib.mkEnableOption "UniFi Endpoint, Ubiquiti's UniFi network access client";

            users = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              example = [ "alice" ];
              description = ''
                Users to add to the `unifi-endpoint` group.

                Membership is only required for installing and removing workspace CA
                certificates into the system trust store. The privileged helper checks
                it directly (`id -nG $PKEXEC_UID`), because pkexec authorises all of the
                helper's subcommands against a single polkit action and therefore cannot
                gate the trust-store operations on its own. VPN, WiFi and 802.1X do not
                need it.

                Without this, CA installation fails for every user.
              '';
            };
          };

          config = lib.mkIf cfg.enable {
            assertions = [
              {
                assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
                message = "services.unifi-endpoint: the upstream .deb is amd64-only.";
              }
            ];

            warnings = lib.optional (!config.networking.networkmanager.enable) ''
              services.unifi-endpoint is enabled but networking.networkmanager.enable is
              not. WiFi onboarding, 802.1X wired auth and VPN DNS all go through nmcli
              and will fail.
            '';

            environment = {
              systemPackages = [
                pkg
                pkgs.wireguard-tools
                pkgs.libsecret
                pkgs.xdg-utils
                pkgs.libnotify
              ];

              etc = {
                "polkit-1/rules.d/50-unifi-endpoint.rules".source =
                  "${pkg}/share/unifi-endpoint/50-unifi-endpoint.rules";
                "ssl/certs/ca-certificates.crt".source = lib.mkForce runtimeBundle;
                "ssl/certs/ca-bundle.crt".source = lib.mkForce runtimeBundle;
                "pki/tls/certs/ca-bundle.crt".source = lib.mkForce runtimeBundle;
              }
              // lib.optionalAttrs config.networking.networkmanager.enable {
                "NetworkManager/conf.d/90-unifi-endpoint-unmanaged-vpn.conf".source =
                  "${pkg}/share/unifi-endpoint/90-unifi-endpoint-unmanaged-vpn.conf";
              };
            };

            services.gvfs.enable = lib.mkDefault true;

            security.polkit = {
              enable = true;
              enablePkexecWrapper = true;
            };

            users.groups.unifi-endpoint.members = cfg.users;

            system.activationScripts = {
              unifiEndpointTrustStore = {
                deps = [ ];
                text = lib.getExe rebuildTrustStore;
              };
              etc.deps = [ "unifiEndpointTrustStore" ];
            };

            systemd = {
              mounts = [
                {
                  description = "UniFi Endpoint program directory";
                  what = "${pkg}/lib/UniFi-Endpoint";
                  where = fhsDir;
                  type = "none";
                  options = "bind,ro,nosuid,nodev";
                  wantedBy = [ "multi-user.target" ];
                  before = [ "display-manager.service" ];
                }
              ];

              tmpfiles.rules = [
                "d /var/lib/UniFi-Endpoint 0700 root root -"
                "L+ /usr/bin/gio - - - - ${pkgs.glib.bin}/bin/gio"
                "d ${anchorDir} 0755 root root -"
                "d ${hookDir} 0755 root root -"
                "L+ ${hookDir}/update-ca-certificates - - - - ${lib.getExe rebuildTrustStore}"
              ];

              services.unifi-endpoint-trust-store = {
                description = "Rebuild the UniFi Endpoint-augmented CA trust store";
                serviceConfig = {
                  Type = "oneshot";
                  ExecStart = lib.getExe rebuildTrustStore;
                };
              };

              paths.unifi-endpoint-trust-store = {
                description = "Watch for UniFi Endpoint CA anchor changes";
                wantedBy = [ "multi-user.target" ];
                pathConfig.PathChanged = anchorDir;
              };

              user = {
                sockets."UniFi-Endpoint-Daemon" = {
                  description = "UniFi Endpoint user daemon socket";
                  wantedBy = [ "sockets.target" ];
                  socketConfig = {
                    ListenStream = "%t/UniFi-Endpoint-service.sock";
                    SocketMode = "0600";
                  };
                };

                services."UniFi-Endpoint-Daemon" = {
                  description = "UniFi Endpoint user daemon";
                  requires = [ "UniFi-Endpoint-Daemon.socket" ];
                  after = [ "UniFi-Endpoint-Daemon.socket" ];
                  serviceConfig = {
                    Type = "simple";
                    ExecStart = "${pkg}/lib/UniFi-Endpoint/UniFi-Endpoint-Daemon";
                    Environment = [ "PATH=/run/wrappers/bin:/run/current-system/sw/bin" ];
                    UnsetEnvironment = [ "SHELL" ];
                    NoNewPrivileges = false;
                    KillSignal = "SIGTERM";
                    TimeoutStopSec = 10;
                    Restart = "on-failure";
                    RestartSec = 5;
                  };
                  restartIfChanged = false;
                };
              };
            };
          };
        };
    }
    // flake-utils.lib.eachDefaultSystem (
      system:
      let
        fmt = treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} ./treefmt.nix;
      in
      {
        formatter = fmt.config.build.wrapper;
        checks.formatting = fmt.config.build.check self;
      }
    );
}
