# Smart abbreviations for common commands
# Puffer-fish provides context-aware text expansions

# Git abbreviations
abbr -a gs git status
abbr -a ga git add
abbr -a gc git commit
abbr -a gp git push
abbr -a gpl git pull
abbr -a gd git diff
abbr -a gco git checkout
abbr -a gcb git checkout -b
abbr -a gl git log --oneline
abbr -a gll git log --oneline --graph --all
abbr -a gf git fetch
abbr -a gb git branch
abbr -a gm git merge
abbr -a gr git rebase
abbr -a gri git rebase -i
abbr -a gst git stash
abbr -a gstp git stash pop

# Docker abbreviations
abbr -a d docker
abbr -a dc docker compose
abbr -a dcu docker compose up
abbr -a dcd docker compose down
abbr -a dcl docker compose logs
abbr -a dps docker ps
abbr -a dpsa docker ps -a
abbr -a di docker images
abbr -a drm docker rm
abbr -a drmi docker rmi

# Kubernetes abbreviations (in addition to aliases)
abbr -a kx kubectx
abbr -a kn kubens

# System abbreviations
abbr -a ll ls -la
abbr -a la ls -A
abbr -a l ls -CF

# Nix abbreviations (in addition to aliases)
abbr -a nb nix build
abbr -a nd nix develop
abbr -a ns nix shell
abbr -a nfl nix flake lock
abbr -a nfs nix flake show

# Quick directory navigation
# Note: Use 'prevd' for going back (Fish built-in), '-' alias not supported
abbr -a .. cd ..
abbr -a ... cd ../..
abbr -a .... cd ../../..

# Misc
abbr -a h history
abbr -a c clear
abbr -a q exit
