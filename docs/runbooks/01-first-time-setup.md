# First-time setup
1. `./scripts/setup-git.sh` (gh -> midega-g, git init, local identity).
2. Secret scanning and pre-commit hooks (once per machine, then once per clone):
   ```bash
   pipx install pre-commit
   # betterleaks: stable release binary, checksum-verified (the hook uses the binary on PATH)
   V=1.10.1; B=https://github.com/betterleaks/betterleaks/releases/download/v$V
   cd "$(mktemp -d)" && curl -fsSLO "$B/betterleaks_${V}_linux_x64.tar.gz" \
     && curl -fsSL "$B/checksums.txt" -o sums.txt \
     && grep linux_x64.tar.gz sums.txt | sha256sum -c - \
     && tar xzf "betterleaks_${V}_linux_x64.tar.gz" betterleaks \
     && install -m 755 betterleaks ~/.local/bin/ && cd -
   betterleaks version              # expect 1.10.1
   pre-commit install               # in the repo root: adds .git/hooks/pre-commit
   pre-commit run --all-files       # all Passed
   ```
   Keep `V` in step with `rev:` in `.pre-commit-config.yaml`. Use stable releases only (no `-rc`).
3. `snow` CLI must be installed (`snow --version`). snowsql is not used.
4. Install the VS Code "Snowflake" extension. It reads `~/.snowflake/connections.toml`; either copy the rendered project connection there or launch VS Code from a shell where `source scripts/use-project.sh <proj>` was run (sets `SNOWFLAKE_HOME`).
5. `cp projects/<p>/.env.example projects/<p>/.env`, fill account/user/password.
6. Edit `projects/<p>/bootstrap.conf`, `roles.csv`, `schemas.csv`.
7. `source scripts/use-project.sh <p>` then `snow connection test -c <conn>_boot`.
8. See `03-bootstrap.md`.
