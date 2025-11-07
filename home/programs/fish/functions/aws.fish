function agp --description "Show current AWS profile"
    echo $AWS_PROFILE
end

function agr --description "Show current AWS region"
    echo $AWS_REGION
end

function asp --description "Set AWS profile"
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_PROFILE AWS_PROFILE AWS_EB_PROFILE AWS_PROFILE_REGION
        echo "AWS profile cleared."
        return
    end

    # Check if profile exists
    set -l available_profiles (aws configure list-profiles 2>/dev/null)
    if not contains -- $argv[1] $available_profiles
        echo (set_color red)"Profile '$argv[1]' not found in AWS config"(set_color normal) >&2
        echo "Available profiles: $available_profiles" >&2
        return 1
    end

    set -gx AWS_DEFAULT_PROFILE $argv[1]
    set -gx AWS_PROFILE $argv[1]
    set -gx AWS_EB_PROFILE $argv[1]
    
    set -gx AWS_PROFILE_REGION (aws configure get region 2>/dev/null)

    # Handle SSO login/logout
    if test "$argv[2]" = "login"
        if test -n "$argv[3]"
            aws sso login --sso-session $argv[3]
        else
            aws sso login
        end
    else if test "$argv[2]" = "logout"
        aws sso logout
    end
end

function asr --description "Set AWS region"
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_REGION AWS_REGION
        echo "AWS region cleared."
        return
    end

    # List of common AWS regions (you can expand this)
    set -l common_regions \
        us-east-1 us-east-2 us-west-1 us-west-2 \
        eu-west-1 eu-west-2 eu-west-3 eu-central-1 \
        ap-southeast-1 ap-southeast-2 ap-northeast-1 \
        ca-central-1 sa-east-1

    set -gx AWS_REGION $argv[1]
    set -gx AWS_DEFAULT_REGION $argv[1]
    echo "AWS region set to $argv[1]"
end

function acp --description "Switch AWS profile with credentials"
    if test -z "$argv[1]"
        set -e AWS_DEFAULT_PROFILE AWS_PROFILE AWS_EB_PROFILE
        set -e AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
        echo "AWS profile cleared."
        return
    end

    set -l available_profiles (aws configure list-profiles 2>/dev/null)
    if not contains -- $argv[1] $available_profiles
        echo (set_color red)"Profile '$argv[1]' not found in AWS config"(set_color normal) >&2
        echo "Available profiles: $available_profiles" >&2
        return 1
    end

    set -gx AWS_PROFILE $argv[1]
    set -gx AWS_DEFAULT_PROFILE $argv[1]
    set -gx AWS_EB_PROFILE $argv[1]
    
    echo "Switched to AWS profile: $argv[1]"
end

function aws_profiles --description "List all AWS profiles"
    aws configure list-profiles 2>/dev/null
end
