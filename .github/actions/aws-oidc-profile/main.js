const { execSync } = require("child_process");

const roleArn = process.env.INPUT_ROLE_ARN || process.env["INPUT_ROLE-ARN"];
const awsRegion =
  process.env.INPUT_AWS_REGION || process.env["INPUT_AWS-REGION"];
const profileName =
  process.env.INPUT_PROFILE_NAME ||
  process.env["INPUT_PROFILE-NAME"] ||
  "default";
const tokenFile = "/tmp/github_oidc_token.txt";

function run(cmd) {
  execSync(cmd, { stdio: "inherit", shell: "/bin/bash" });
}

run(`set -euo pipefail

# Fetch a fresh OIDC token from GitHub Actions
fetch_oidc_token() {
  curl -sS \\
    -H "Authorization: bearer \${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \\
    -H "Accept: application/json; api-version=2.0" \\
    -H "Content-Type: application/json" \\
    -d '{"audience":"sts.amazonaws.com"}' \\
    "\${ACTIONS_ID_TOKEN_REQUEST_URL}" | jq -r '.value'
}

# Get initial token
echo "Fetching initial OIDC token..."
OIDC_TOKEN=$(fetch_oidc_token)
if [ -z "$OIDC_TOKEN" ] || [ "$OIDC_TOKEN" = "null" ]; then
  echo "::error::Failed to fetch OIDC token. Ensure id-token: write permission is set."
  exit 1
fi
echo "$OIDC_TOKEN" > "${tokenFile}"
chmod 600 "${tokenFile}"

# Start background token refresher (every 4 min; tokens expire ~5 min)
(
  while true; do
    sleep 240
    TOKEN=$(fetch_oidc_token 2>/dev/null || true)
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
      echo "$TOKEN" > "${tokenFile}"
    fi
  done
) &
REFRESHER_PID=$!
echo "OIDC token refresher started (PID $REFRESHER_PID)"

# Configure AWS CLI profile
mkdir -p ~/.aws
cat >> ~/.aws/config << AWSEOF
[profile ${profileName}]
role_arn = ${roleArn}
web_identity_token_file = ${tokenFile}
region = ${awsRegion}
AWSEOF
chmod 600 ~/.aws/config

# Export for subsequent steps and post cleanup
echo "AWS_PROFILE=${profileName}" >> "$GITHUB_ENV"
echo "AWS_DEFAULT_REGION=${awsRegion}" >> "$GITHUB_ENV"
echo "OIDC_REFRESHER_PID=$REFRESHER_PID" >> "$GITHUB_ENV"
echo "OIDC_TOKEN_FILE=${tokenFile}" >> "$GITHUB_ENV"

# Also save state for the post step (GITHUB_ENV isn't available in post)
echo "OIDC_REFRESHER_PID=$REFRESHER_PID" >> "$GITHUB_STATE"
echo "OIDC_TOKEN_FILE=${tokenFile}" >> "$GITHUB_STATE"

# Verify credentials work (skip if aws CLI not yet installed)
if command -v aws &>/dev/null; then
  CALLER=$(aws sts get-caller-identity --query 'Arn' --output text 2>&1) || {
    echo "::error::AWS credential verification failed: $CALLER"
    kill "$REFRESHER_PID" 2>/dev/null || true
    exit 1
  }
  echo "Authenticated as: $CALLER"
else
  echo "AWS CLI not in PATH — skipping credential verification (will be verified on first use)"
fi
`);
