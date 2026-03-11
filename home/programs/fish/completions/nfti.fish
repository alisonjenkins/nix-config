set -l templates go go-lambda java java-lambda node node-lambda python python-lambda rust rust-lambda typescript typescript-lambda
complete -c nfti -f -a "$templates"
complete -c nix-flake-template-init -f -a "$templates"
