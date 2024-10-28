{ pkgs, lib }: pkgs.rustPlatform.buildRustPackage rec {
  pname = "git-clean";
  version = "24.10.28";
  doCheck = false;

  src = pkgs.fetchFromGitHub {
    owner = "alisonjenkins";
    repo = pname;
    rev = "68e74a6527e1d3d0b1b4dc533f61e79a6fb998e9";
    hash = "sha256-t3ISimoPgqOeerXU2pVifm5DLuqzebjqK/lZAYysxho=";
  };

  cargoHash = "sha256-foer9213FhS6m09mvJsNifxwRikDvE+1PF8R+6w6WLc=";

  meta = {
    description = "Cleans up merged local and remote git branches";
    homepage = "https://github.com/mcasper/git-clean";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
