# Git
- Remote: `github.com/midega-g/snowflake-projects` (public). GitHub account: `midega-g`. `scripts/setup-git.sh` runs `gh auth switch -u midega-g` and sets local identity.
- Branch per change (`feat/...`, `fix/...`); small commits, imperative messages. Don't push to `main` directly once a remote exists.
- Pre-commit hooks must pass (`.pre-commit-config.yaml`): betterleaks secret scan on staged changes, private-key detection, large files, YAML/TOML, whitespace. Never use `git commit --no-verify`. Before every push: `pre-commit run --all-files`.
- Secret scanner is **betterleaks** (stable releases only), not gitleaks. Full-history check before making anything public: `betterleaks git . --redact`.
- A gitleaks binary (`~/.local/bin/gitleaks`, 8.30.1) may exist on the machine. Other projects outside this repo use it for their local scans, so leave it installed. Nothing in this repo calls it; don't add it to hooks or scripts here.
- Never commit `.env`, keys, `profiles.yml`, `.snowflake/` (rendered connections).
