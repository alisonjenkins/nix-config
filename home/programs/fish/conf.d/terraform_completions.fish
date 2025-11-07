# Enable terraform completions
if type -q terraform
    terraform -install-autocomplete 2>/dev/null
end

# Enable terragrunt completions if available
if type -q terragrunt
    # Terragrunt uses similar completion to terraform
    complete -c terragrunt -w terraform
end

# Enable tofu completions if available
if type -q tofu
    tofu -install-autocomplete 2>/dev/null
end
