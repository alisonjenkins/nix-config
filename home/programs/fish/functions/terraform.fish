# Terraform prompt info function
function tf_prompt_info --description "Show current Terraform workspace"
    # Don't show 'default' workspace in home dir
    if test "$PWD" = "$HOME"
        return
    end
    
    # Check if in terraform dir
    if test -d .terraform
        set -l workspace (terraform workspace show 2>/dev/null)
        if test -n "$workspace"
            echo "[$workspace]"
        end
    end
end

# Terraform aliases
alias tf='terraform'

alias tfi='tf init'

alias tfp='tf plan'
alias tfip='tfi && tfp'

alias tfa='tf apply'
alias tfia='tfi && tfa'

alias tfd='tf destroy'
alias tfid='tfi && tfd'

# DANGER zone
alias 'tfa!'='tfa -auto-approve'
alias 'tfia!'='tfi && tfa -auto-approve'

# DANGER++!!
alias 'tfd!'='tfd -auto-approve'
alias 'tfid!'='tfi && tfd -auto-approve'

alias tfc='tf console'
alias tfg='tf graph'
alias tfget='tf get'
alias tfimp='tf import'
alias tfo='tf output'
alias tfprov='tf providers'
alias tfpp='tf push'
alias tfr='tf refresh'
alias tfs='tf show'
alias tfst='tf state'
alias tft='tf taint'
alias tfunt='tf untaint'
alias tfv='tf validate'
alias tfver='tf version'
alias tfw='tf workspace'
