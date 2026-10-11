#!/bin/bash
# Prepare REA in Claude Code cloud sessions: install locked dependencies, build
# the runtime that the project-scoped `rea` MCP server (.mcp.json) runs, put the
# `rea` CLI on PATH, and provide Ghidra for native analysis.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"

# The Ghidra build REA's bridge is verified against (src/ghidra/GhidraInstallationPolicy.ts).
GHIDRA_VERSION=12.1.4
GHIDRA_ZIP=ghidra_${GHIDRA_VERSION}_PUBLIC_20260921.zip
GHIDRA_SHA256=ddac49f903da9d5bac833e5cc79395098b9c33cfd3279be5f31bd00387d2d4db
GHIDRA_INSTALL_DIR=/opt/ghidra_${GHIDRA_VERSION}_PUBLIC

install_ghidra() {
  local tmp
  tmp=$(mktemp -d)
  if curl -fsSL -o "$tmp/$GHIDRA_ZIP" \
    "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_${GHIDRA_VERSION}_build/$GHIDRA_ZIP" &&
    echo "$GHIDRA_SHA256  $tmp/$GHIDRA_ZIP" | sha256sum --check --quiet - &&
    unzip -q "$tmp/$GHIDRA_ZIP" -d "$tmp/extract"; then
    mv "$tmp/extract/ghidra_${GHIDRA_VERSION}_PUBLIC" "$GHIDRA_INSTALL_DIR"
  else
    echo "Ghidra ${GHIDRA_VERSION} could not be installed; native analysis is unavailable." >&2
  fi
  rm -rf "$tmp"
}

# SessionStart stdout becomes session context; keep tool output on stderr.
{
  # The container is cached after this hook, so reinstall only when the
  # installed direct dependencies no longer match package-lock.json.
  if ! node scripts/check-dependency-install.mjs; then
    npm ci --no-audit --no-fund
  fi
  # Turbo-cached: rebuilds only when sources or inputs changed.
  TURBO_TELEMETRY_DISABLED=1 npm run build:cached
  # Expose this checkout as the global `rea` command.
  if [ "$(readlink -f "$(command -v rea || true)")" != "$PWD/scripts/rea.mjs" ]; then
    npm link --no-audit --no-fund
  fi
  if [ ! -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]; then
    install_ghidra
  fi
} >&2

ghidra_status="Ghidra is unavailable"
if [ -x "$GHIDRA_INSTALL_DIR/support/analyzeHeadless" ]; then
  ghidra_status="Ghidra ${GHIDRA_VERSION} is at $GHIDRA_INSTALL_DIR"
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "export GHIDRA_INSTALL_DIR=$GHIDRA_INSTALL_DIR" >>"$CLAUDE_ENV_FILE"
  fi
fi

echo "REA $(rea --version) is built and on PATH as \`rea\`; the project MCP server \`rea\` runs this checkout. $ghidra_status."
