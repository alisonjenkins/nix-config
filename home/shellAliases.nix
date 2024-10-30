{ pkgs }: {
  "-- -" = "cd -";
  ".." = "cd ..";
  "..." = "cd ../..";
  "...." = "cd ../../..";
  "....." = "cd ../../../..";
  "cdd" = "cd ~/Downloads/";
  "cdg" = "cd ~/git/";
  "cdgo" = "cd \$GOPATH";
  "cdot" = "cd ~/.local/share/chezmoi";
  "gc" = "${pkgs.callPackage ../pkgs/git-clean { inherit pkgs; }}/bin/git-clean";
  "j" = "just";
  "key" = "ssh-add ~/.ssh/ssh_keys/id_bashton_alan";
  "keyaur" = "ssh-add ~/.ssh/ssh_keys/id_aur";
  "keyb" = "ssh-add ~/.ssh/ssh_keys/id_bashton";
  "keycl" = "ssh-add -D";
  "keyk" = "ssh-add ~/.ssh/ssh_keys/id_krystal";
  "keyp" = "ssh-add ~/.ssh/ssh_keys/id_personal";
  "keypa" = "ssh-add ~/.ssh/ssh_keys/id_alan-aws";
  "keypo" = "ssh-add ~/.ssh/ssh_keys/id_personal_old";
  "kmse" = "export EYAML_CONFIG=$PWD/.kms-eyaml.yaml";
  "ll" = "${pkgs.eza}/bin/eza -l --grid --git";
  "ls" = "${pkgs.eza}/bin/eza";
  "lt" = "${pkgs.eza}/bin/eza --tree --git --long";
  "pwhash" = "python -c \"import crypt,getpass; print(crypt.crypt(getpass.getpass(), crypt.mksalt(crypt.METHOD_SHA512)))\"";
  "vi" = "nvim";
  "vim" = "nvim";
}
