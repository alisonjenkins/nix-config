_nix_flake_template_init() {
  local -a templates
  templates=(
    'go:Go project'
    'go-lambda:AWS Lambda Go project'
    'java:Java project with Maven'
    'java-lambda:AWS Lambda Java project'
    'node:Node.js project'
    'node-lambda:AWS Lambda Node.js project'
    'python:Python project'
    'python-lambda:AWS Lambda Python project'
    'rust:Rust project with crane'
    'rust-lambda:AWS Lambda Rust project'
    'typescript:TypeScript project'
    'typescript-lambda:AWS Lambda TypeScript project'
  )
  _describe 'template' templates
}
compdef _nix_flake_template_init nix-flake-template-init
compdef _nix_flake_template_init nfti
