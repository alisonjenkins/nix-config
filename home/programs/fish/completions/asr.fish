# Completion for asr (AWS Set Region) command
complete -c asr -f

# First argument: AWS region names
complete -c asr -n "__fish_is_first_arg" -a "us-east-1 us-east-2 us-west-1 us-west-2" -d "US regions"
complete -c asr -n "__fish_is_first_arg" -a "eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-north-1 eu-south-1" -d "Europe regions"
complete -c asr -n "__fish_is_first_arg" -a "ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2 ap-northeast-3 ap-south-1 ap-east-1" -d "Asia Pacific regions"
complete -c asr -n "__fish_is_first_arg" -a "ca-central-1" -d "Canada regions"
complete -c asr -n "__fish_is_first_arg" -a "sa-east-1" -d "South America regions"
complete -c asr -n "__fish_is_first_arg" -a "me-south-1" -d "Middle East regions"
complete -c asr -n "__fish_is_first_arg" -a "af-south-1" -d "Africa regions"
