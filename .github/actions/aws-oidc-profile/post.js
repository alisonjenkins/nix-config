const { execSync } = require("child_process");

const pid = process.env.STATE_OIDC_REFRESHER_PID || "";
const tokenFile =
  process.env.STATE_OIDC_TOKEN_FILE || "/tmp/github_oidc_token.txt";

try {
  execSync(
    `
    if [ -n "${pid}" ]; then
      kill "${pid}" 2>/dev/null && echo "Stopped OIDC token refresher (PID ${pid})" || echo "OIDC refresher already stopped"
    fi
    rm -f "${tokenFile}"
    rm -f ~/.aws/config
  `,
    { stdio: "inherit", shell: "/bin/bash" },
  );
} catch {
  // Best-effort cleanup — don't fail the job
}
