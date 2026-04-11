# Enable terraform completions
if type -q terraform; and not test -s ~/.config/fish/completions/terraform.fish
    terraform -install-autocomplete 2>/dev/null
end

if type -q terragrunt
    complete -c terragrunt -w terraform
end

if type -q tofu; and not test -s ~/.config/fish/completions/tofu.fish
    tofu -install-autocomplete 2>/dev/null
end
