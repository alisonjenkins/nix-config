{ lib
, stdenv
, fetchurl
, fetchFromGitHub
, fetchzip
, fetchgit
, curl
, jq
, writeShellScriptBin
}:

let
  # Helper function to fetch a single wallpaper
  fetchWallpaper = { name, url, sha256 }:
    fetchurl {
      inherit url sha256;
      name = "${name}";
    };

  # Helper function to fetch wallpapers from Unsplash
  fetchFromUnsplash = { photoId, name ? "unsplash-${photoId}.jpg", width ? 1920, height ? 1080, sha256 }:
    fetchurl {
      url = "https://unsplash.com/photos/${photoId}/download?w=${toString width}&h=${toString height}";
      inherit name sha256;
    };

  # Helper function to fetch wallpapers from a GitHub repository
  fetchWallpapersFromGitHub = { owner, repo, rev, directory ? "", sha256 }:
     fetchgit {
        inherit rev;
        url = "https://github.com/${owner}/${repo}.git";
        fetchLFS = true;
        sparseCheckout = [
          directory
        ];
        hash = sha256;
      };

  # Helper function to fetch wallpapers from wallhaven.cc
  fetchFromWallhaven = { id, name ? "wallhaven-${id}.jpg", sha256 }:
    fetchurl {
      url = "https://w.wallhaven.cc/full/${builtins.substring 0 2 id}/wallhaven-${id}.jpg";
      inherit name sha256;
    };

  # Helper script to search wallhaven
  wallhavenSearch = writeShellScriptBin "wallhaven-search" ''
    #!/usr/bin/env bash
    # Usage: wallhaven-search "query" [page]

    QUERY="$1"
    PAGE="''${2:-1}"

    ${curl}/bin/curl -s "https://wallhaven.cc/api/v1/search?q=$QUERY&page=$PAGE" | \
      ${jq}/bin/jq -r '.data[] | "ID: \(.id) - Resolution: \(.resolution) - URL: \(.path)"'
  '';

in
stdenv.mkDerivation {
  pname = "wallpapers";
  version = "2.0.0";

  # This is just a builder package - no source needed
  src = ./.;

  # Example of how to use the helper functions
  buildInputs = [
    wallhavenSearch
  ];

  # Example of how to include wallpapers in the package
  # Replace these with actual wallpapers you want to include
  passthru.examples = {
    singleWallpaper = fetchWallpaper {
      name = "example.jpg";
      url = "https://example.com/wallpaper.jpg";
      sha256 = "";
    };

    unsplashWallpaper = fetchFromUnsplash {
      photoId = "abcdef123456";
      width = 3840;
      height = 2160;
      sha256 = "";
    };

    githubWallpapers = fetchWallpapersFromGitHub {
      owner = "username";
      repo = "wallpapers";
      rev = "main";
      sha256 = "";
    };

    wallhavenWallpaper = fetchFromWallhaven {
      id = "abcdef";
      sha256 = "";
    };
  };

  installPhase = ''
    mkdir -p $out/share/wallpapers

    ALI_WALLPAPERS=${fetchWallpapersFromGitHub {
      owner = "alisonjenkins";
      repo = "nix-config";
      rev = "aba1d527cb98e3aed5c11d374e3879fa691c55c9";
      directory = "pkgs/wallpapers/wallpapers";
      sha256 = "sha256-2Zu2R27UygPa96wWZDjJPBvjEmvbRq1DzwAWB6NT5RM=";
    }}

    cd "$ALI_WALLPAPERS/pkgs/wallpapers/wallpapers" && cp -R . $out/share/wallpapers/

    ETHAN_FREEDOM_GUNDAM_CALL_OF_DUTY_MOBILE=${fetchWallpaper {
      name = "ethan-freedom-gundam-call-of-duty-mobile-xf-2560x1600.jpg";
      url = "https://images.hdqwalls.com/download/ethan-freedom-gundam-call-of-duty-mobile-xf-2560x1600.jpg";
      sha256 = "sha256-W/ZzQOCbxdGd4Xgq6Kpkqkdm9SpaxywP1aiFU+8lZBE=";
    }}

    cp "$ETHAN_FREEDOM_GUNDAM_CALL_OF_DUTY_MOBILE" $out/share/wallpapers/

    # Install the wallhaven search utility
    mkdir -p $out/bin
    ln -s ${wallhavenSearch}/bin/wallhaven-search $out/bin/
  '';

  meta = with lib; {
    description = "A collection of wallpapers from various sources";
    license = licenses.cc0; # Creative Commons Zero - public domain equivalent
    platforms = platforms.all;
    maintainers = [];
  };
}
