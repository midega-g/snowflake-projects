#!/usr/bin/env bash
# Provision a project's Snowflake objects from its config, step by step, via `snow sql`.
# Usage: scripts/bootstrap.sh <project> [--phase 1|2|all] [--step NAME]... [--conn NAME] [--dry-run] [--teardown]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJ=""; PHASE=all; DRY=0; CONN=""; TEARDOWN=0; ONLY=()
while (($#)); do case "$1" in
  --phase) PHASE="$2"; shift;; --step) ONLY+=("$2"); shift;; --conn) CONN="$2"; shift;;
  --dry-run) DRY=1;; --teardown) TEARDOWN=1;;
  -h|--help) sed -n '2,3p' "$0"; exit 0;; *) PROJ="$1";; esac; shift; done
[ -n "$PROJ" ] || { sed -n '2,3p' "$0"; exit 1; }
PDIR="$ROOT/projects/$PROJ"; CONF="$PDIR/bootstrap.conf"; STEPS="$ROOT/bootstrap/steps"
[ -f "$CONF" ] || { echo "Missing $CONF"; exit 1; }

# --- parse KEY=VALUE config (not sourced: no code execution) ---
declare -A V
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; line="${line//$'\r'/}"
  [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
  k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
  v="${v%"${v##*[![:space:]]}"}"; v="${v#\"}"; v="${v%\"}"; V[$k]="$v"
done < "$CONF"
: "${V[PROJECT_KEY]:?PROJECT_KEY required}" "${V[WH_NAME]:?}" "${V[DB_NAME]:?}" "${V[OWNER_ROLE]:?}" "${V[DEFAULT_ROLE]:?}"
: "${V[WH_SIZE]:=XSMALL}" "${V[WH_AUTO_SUSPEND]:=60}" "${V[RM_FREQUENCY]:=MONTHLY}" "${V[RM_QUOTA]:=5}"
: "${V[DB_TRANSIENT]:=N}" "${V[DB_RETENTION_DAYS]:=1}" "${V[TAG_SCHEMA]:=GOVERNANCE}" "${V[DEFAULT_SCHEMA]:=STAGING}"
: "${V[PHASE1_STEPS]:=roles resource_monitor warehouse}" "${V[PHASE2_STEPS]:=database schemas grants tags user_defaults}"
rn() { echo "${V[PROJECT_KEY]}_$1"; }
V[OWNER_ROLE]="$(rn "${V[OWNER_ROLE]}")"; V[DEFAULT_ROLE]="$(rn "${V[DEFAULT_ROLE]}")"
[ "${V[DB_TRANSIENT]}" = Y ] && V[DB_KW]=TRANSIENT || V[DB_KW]="/*std*/"

COMMON_D=(); for k in "${!V[@]}"; do COMMON_D+=(-D "${k,,}=${V[$k]}"); done
SNOW=(snow sql); [ -n "$CONN" ] || CONN="${V[CONNECTION]:-}_boot"
[ "$CONN" != "_boot" ] && SNOW+=(-c "$CONN")
if ((!DRY)) && [ -z "${SNOWFLAKE_HOME:-}" ]; then
  echo "SNOWFLAKE_HOME unset: run 'source scripts/use-project.sh $PROJ' first (or use --dry-run)"; exit 1; fi

# run_sql <template> [-D k=v ...]  (project-local template overrides shared one)
run_sql() {
  local f="$1"; shift; local p="$PDIR/bootstrap/$f.sql"
  [ -f "$p" ] || p="$STEPS/$f.sql"; [ -f "$p" ] || p="$ROOT/bootstrap/optional/$f.sql"
  [ -f "$p" ] || { echo "no template for step '$f'"; exit 1; }
  local cmd=("${SNOW[@]}" -f "$p" "${COMMON_D[@]}" "$@"); echo ">> $f $*"
  if ((DRY)); then printf '   %q ' "${cmd[@]}"; echo; else "${cmd[@]}"; fi
}
rows() { [ -f "$1" ] && grep -vE '^[[:space:]]*(#|$)' "$1" | tr -d '\r' || true; }
ROLES="$PDIR/roles.csv"; SCHEMAS="$PDIR/schemas.csv"

step_roles() {
  while IFS=, read -r suf parent _ _; do run_sql roles_create -D "role_name=$(rn "$suf")"; done < <(rows "$ROLES")
  while IFS=, read -r suf parent _ _; do
    if rows "$ROLES" | cut -d, -f1 | grep -qx "$parent"; then parent="$(rn "$parent")"; fi
    run_sql roles_link -D "role_name=$(rn "$suf")" -D "parent_role=$parent"
  done < <(rows "$ROLES")
}
step_warehouse() {
  run_sql warehouse
  [[ " ${V[PHASE1_STEPS]} " == *" resource_monitor "* ]] && run_sql warehouse_attach_monitor
  run_sql warehouse_ownership
}
step_schemas() {
  while IFS=, read -r name transient managed; do
    local kw="/*std*/" mg="/*unmanaged*/"; [ "$transient" = Y ] && kw=TRANSIENT; [ "$managed" = Y ] && mg="WITH MANAGED ACCESS"
    run_sql schemas -D "schema_name=$name" -D "schema_kw=$kw" -D "schema_managed=$mg"
  done < <(rows "$SCHEMAS")
}
step_grants() {
  while IFS=, read -r suf _ db wh; do
    local r; r="$(rn "$suf")"
    case "$db" in
      READ)      run_sql grants_db -D "role_name=$r" -D "schema_privs=USAGE" -D "object_privs=SELECT";;
      READWRITE) run_sql grants_db -D "role_name=$r" -D "schema_privs=ALL"   -D "object_privs=ALL";;
      OWNER|NONE|"") ;; *) echo "bad db_access '$db' for $suf"; exit 1;;
    esac
    [ -n "$wh" ] && [ "$wh" != NONE ] && run_sql grants_wh -D "role_name=$r" -D "wh_privs=${wh//+/, }"
  done < <(rows "$ROLES")
}
step_teardown() {
  read -r -p "DROP ${V[DB_NAME]}, ${V[WH_NAME]}, ${V[RM_NAME]:-} and all project roles? type project key (${V[PROJECT_KEY]}): " a
  [ "$a" = "${V[PROJECT_KEY]}" ] || { echo aborted; exit 1; }
  run_sql teardown_objects
  while IFS=, read -r suf _; do run_sql teardown_role -D "role_name=$(rn "$suf")"; done < <(rows "$ROLES")
}

run_step() { if declare -F "step_$1" >/dev/null; then "step_$1"; else run_sql "$1"; fi; }
if ((TEARDOWN)); then ((DRY)) || true; step_teardown; exit 0; fi
if ((${#ONLY[@]})); then list=("${ONLY[@]}")
else case "$PHASE" in 1) list=(${V[PHASE1_STEPS]});; 2) list=(${V[PHASE2_STEPS]});;
  all) list=(${V[PHASE1_STEPS]} ${V[PHASE2_STEPS]});; *) echo "bad --phase"; exit 1;; esac; fi
for s in "${list[@]}"; do run_step "$s"; done
echo "done: ${list[*]}"
