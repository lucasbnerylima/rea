#!/bin/bash
# Prepare REA in Claude Code cloud sessions: install locked dependencies and
# build the runtime that the project-scoped `rea` MCP server (.mcp.json) runs.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# SessionStart stdout becomes session context; keep tool output on stderr.
{
  # The container is cached after this hook, so reinstall only when the
  # installed direct dependencies no longer match package-lock.json.
  if ! node scripts/check-dependency-install.mjs; then
    npm ci --no-audit --no-fund
  fi
  # Turbo-cached: rebuilds only when sources or inputs changed.
  TURBO_TELEMETRY_DISABLED=1 npm run build:cached
} >&2

echo "REA $(node scripts/rea.mjs --version) is built; the project MCP server \`rea\` runs it from scripts/rea.mjs."
