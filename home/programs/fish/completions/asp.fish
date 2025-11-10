# Completion for asp (AWS Set Profile) command
complete -c asp -f

# First argument: AWS profile names
complete -c asp -n "__fish_is_first_arg" -a "(aws configure list-profiles 2>/dev/null)"

# Second argument: login or logout
complete -c asp -n "not __fish_is_first_arg; and test (count (commandline -opc)) -eq 2" -a "login logout"

# Third argument (SSO session name) - only when second arg is 'login'
# This would require listing SSO sessions from ~/.aws/config, left as simple completion
complete -c asp -n "test (count (commandline -opc)) -eq 3; and string match -q login (commandline -opc)[-1]" -d "SSO session name"
