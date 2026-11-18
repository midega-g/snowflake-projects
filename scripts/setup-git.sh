#!/usr/bin/env bash
# Switch gh to midega-g, init repo, set LOCAL git identity. Idempotent.
set -euo pipefail
GH_USER="${GH_USER:-midega-g}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
gh auth switch -u "$GH_USER"
gh auth setup-git >/dev/null 2>&1 || true
[ -d .git ] || git init -b main
git config user.name "$GH_USER"
# use GitHub noreply email to avoid leaking a real address
GH_ID="$(gh api user --jq .id)"
git config user.email "${GH_ID}+${GH_USER}@users.noreply.github.com"
echo "gh active: $(gh api user --jq .login) | git identity: $(git config user.name) <$(git config user.email)>"
