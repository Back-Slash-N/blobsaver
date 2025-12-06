{
  inputs = {
    gradle2nix.url = "github:tadfisher/gradle2nix/v2";
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }@inputs:
  let
    blobsaver-package = pkgs:
      let
        deps = with pkgs; with pkgs.xorg; [
          gtk3
          libXxf86vm
          libXi
          mesa
          libGL
          libXrender
          libXtst
          libXrandr
          libXinerama
          glib
          libimobiledevice
          libplist
          libirecovery
        ];

        libPath = pkgs.lib.makeLibraryPath deps;
        jpackageRoot = "build/jpackage/blobsaver";
      in
      inputs.gradle2nix.builders.${pkgs.stdenv.hostPlatform.system}.buildGradlePackage {
        pname = "blobsaver";
        version = "3.6.0";
        src = ./.;
        lockFile = ./gradle.lock;
        gradleBuildFlags = [ "jpackageImage" "--no-daemon" ];
        jdk = (pkgs.jdk21.override { enableJavaFX = true; });
        nativeBuildInputs = [ pkgs.makeWrapper ];
        runtimeDependencies = deps;
        postInstall = ''
          mkdir -p $out/jpackage
          cp -r ${jpackageRoot}/* $out/jpackage/
          mkdir -p $out/bin
          makeWrapper $out/jpackage/bin/blobsaver $out/bin/blobsaver \
            --prefix LD_LIBRARY_PATH : "${libPath}"
          wrapProgram $out/bin/blobsaver \
            --prefix LD_LIBRARY_PATH : "${pkgs.lib.makeLibraryPath deps}"
        '';
      };

    blobsaver-overlay = final: prev: {
      blobsaver = (blobsaver-package final);
    };

    udevModule = { config, pkgs, lib, ... }: let
      udevRules = ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", MODE="0666"
      '';
    in {
      options.blobsaver = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable blobsaver udev rules for Apple devices.";
        };
      };

      config = lib.mkIf config.blobsaver.enable {
        services.udev.extraRules = udevRules;
        services.avahi = {
          enable = true;
          nssmdns4 = true;
          publish.enable = true;
          publish.userServices = true;
        };
        services.usbmuxd.enable = true;
        environment.systemPackages = [ pkgs.blobsaver ];
      };
    };

  in {
    overlays.default = blobsaver-overlay;
    nixosModules.blobsaver = udevModule;
  };
}
