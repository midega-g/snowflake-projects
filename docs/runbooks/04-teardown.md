# Teardown (destructive, confirm first)
`scripts/bootstrap.sh <project> --teardown` - asks you to type PROJECT_KEY, then drops DB, warehouse, resource monitor and all roles in roles.csv. Not reversible (DB only via Time Travel).
