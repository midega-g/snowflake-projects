#!/usr/bin/env bash
# Usage: source scripts/use-project.sh <project-folder>[/<sub-folder>]
# Run first in each shell: loads env files, renders a per-folder snow connections.toml, points snow at it.
# Env files are loaded from projects/ down to the target folder, so a nested folder (e.g. a lab badge)
# inherits the parent project's settings. At each level: .env (local, gitignored) then badge.env
# (committed, non-secret overrides). Later files win. The nearest connections.toml.template is used.
_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_proj="${1:?project folder required, e.g. 01-dbt-tutorial or 02-snow-hands-on-labs/b05-data-engineering}"
_proj="${_proj%/}"
_dir="$_root/projects/$_proj"
[ -d "$_dir" ] || { echo "No such folder: $_dir"; return 1 2>/dev/null || exit 1; }

_d="$_root/projects"; _found=0; _tpl=""
IFS=/ read -ra _parts <<< "$_proj"
set -a
for _p in "${_parts[@]}"; do
  _d="$_d/$_p"
  [ -f "$_d/.env" ] && { . "$_d/.env"; _found=1; }
  [ -f "$_d/badge.env" ] && . "$_d/badge.env"
  [ -f "$_d/connections.toml.template" ] && _tpl="$_d/connections.toml.template"
done
set +a
((_found)) || { echo "No .env found between projects/ and $_proj (copy .env.example)"; return 1 2>/dev/null || exit 1; }
[ -n "$_tpl" ] || { echo "No connections.toml.template found for $_proj"; return 1 2>/dev/null || exit 1; }

export SNOWFLAKE_HOME="$_dir/.snowflake"
mkdir -p "$SNOWFLAKE_HOME"
( umask 077; envsubst < "$_tpl" > "$SNOWFLAKE_HOME/connections.toml" )
chmod 600 "$SNOWFLAKE_HOME/connections.toml"
export SNOWFLAKE_DEFAULT_CONNECTION_NAME="$PROJECT_CONN"
export SNOWFLAKE_QUERY_TAG="{\"project\":\"$PROJECT_NAME\",\"env\":\"$PROJECT_ENV\",\"owner\":\"$PROJECT_OWNER\"}"
echo "Project: $_proj | conn=$PROJECT_CONN role=${SNOWFLAKE_ROLE:-} wh=${SNOWFLAKE_WAREHOUSE:-<user default>}"
echo "tag=$SNOWFLAKE_QUERY_TAG | template=${_tpl#$_root/} | try: snow connection test"
unset _root _proj _dir _d _found _tpl _parts _p
