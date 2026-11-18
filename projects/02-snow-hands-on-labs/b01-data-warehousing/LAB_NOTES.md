# b01 - Lab notes

Snowflake lessons from setting up this lab: commands, errors, fixes and reasoning. `README.md` has the short version.

Placeholders stand in for real values: `<account>` (`orgname-accountname`), `<user_name>`, `<login_name>`, `<public_key_body>`. Real values live only in the gitignored `../.env` (shared by all badges).

## 1. Get your account details from Snowsight
In Snowsight, open the user menu (bottom-left), then **Account > View account details**. The **Account Details** tab lists the values the CLI needs:

| Snowsight field | Used for |
|---|---|
| Account identifier (`ORGNAME-ACCOUNTNAME`) | `SNOWFLAKE_ACCOUNT` |
| Login name | `SNOWFLAKE_USER` (see section 5) |
| Role | Your default role. Don't use ACCOUNTADMIN as the CLI default |

The **Config File** tab shows a ready-made `connections.toml` snippet. Copy the values into the shared `../.env` and leave the rest. The project renders its own `connections.toml` with the query tag.

Run `SELECT CURRENT_USER();` in a worksheet as well. It returns the **user name**, which can differ from the login name (section 4).

## 2. Why password login failed
```bash
snow connection test
# 390100 (28000): Incorrect username or password was specified.
```
This account signs in through **Google**, which only works in a browser (Snowsight). There is no usable Snowflake password for the CLI.

| CLI auth option | Verdict |
|---|---|
| Snowflake password | Possible after setting one, but weaker, and not what the steering docs prefer |
| `externalbrowser` (SSO) | Opens a browser on each login. Fails in scripts and headless shells |
| Key-pair (`SNOWFLAKE_JWT`) | Chosen: no password, non-interactive, recommended in `02-roles-and-security.md` |

## 3. Create the key pair (local machine)
```bash
mkdir -p ~/.snowflake-keys
chmod 700 ~/.snowflake-keys
cd ~/.snowflake-keys
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -nocrypt -out hol_b01.p8   # private key
openssl rsa -in hol_b01.p8 -pubout -out hol_b01.pub                                # public key
chmod 600 hol_b01.p8
grep -v -- '-----' hol_b01.pub | tr -d '\n'; echo   # public key body for Snowsight
```
- **Private key (`.p8`):** proves who you are. Keep it on your machine, outside the repo.
- **Public key (`.pub`):** given to Snowflake. It's safe to share.
- `-nocrypt` leaves the private key unencrypted. That's acceptable for a learning account protected by file permissions. For anything shared, use an encrypted key and pass the passphrase via `PRIVATE_KEY_PASSPHRASE`.

### File permissions: 700 and 600
Each digit sets permissions for **owner / group / others**. The digit is the sum of read (4), write (2) and execute (1).

| Mode | Owner | Group | Others | Applied to |
|---|---|---|---|---|
| `700` | read, write, enter (`rwx`) | none | none | `~/.snowflake-keys/` directory |
| `600` | read, write (`rw-`) | none | none | `hol_b01.p8` private key, `.env`, rendered `connections.toml` |

- On a directory, "execute" means permission to enter it and reach the files inside. With `700`, no other user on the machine can even list the key folder.
- With `600`, only you can read the file. Some tools refuse keys or config files that other users can read, and the Snowflake CLI warns about a `connections.toml` that is readable by others.
- The `.pub` file can keep its default mode (`644` or `664`, depending on your umask), since it isn't secret.
- Check with `ls -l` (`-rw-------` = 600) or `stat -c '%a %n' ~/.snowflake-keys ~/.snowflake-keys/*`.

## 4. Register the public key (Snowsight)
Open **Projects > Worksheets > + SQL Worksheet** in Snowsight and run:
```sql
USE ROLE ACCOUNTADMIN;          -- or SECURITYADMIN; changing another user's key needs OWNERSHIP on the user
SELECT CURRENT_USER();          -- the exact user name
ALTER USER "<user_name>" SET RSA_PUBLIC_KEY='<public_key_body>';
DESC USER "<user_name>";        -- RSA_PUBLIC_KEY_FP now shows a SHA256 fingerprint
```
`<public_key_body>` is the single line printed in section 3, without the `-----BEGIN/END PUBLIC KEY-----` lines.

You can confirm the key matches by comparing `RSA_PUBLIC_KEY_FP` (shown as `SHA256:<hash>`) with the hash computed locally:
```bash
openssl rsa -pubin -in ~/.snowflake-keys/hol_b01.pub -outform DER 2>/dev/null | openssl dgst -sha256 -binary | openssl enc -base64
```

**Errors we hit along the way:**
| Statement | Result | Why |
|---|---|---|
| `ALTER USER "<login_name>" ...` (the email) | does not exist | The email is the **login name**, not the user name |
| `ALTER USER <USER_NAME> ...` (unquoted) | does not exist | Snowflake uppercases unquoted identifiers. This user was created in lowercase |
| `ALTER USER "<user_name>" ...` (quoted, exact case) | success | Double quotes keep the exact case |

**Lessons:**
- A user has a **name** (the object identifier, used in `ALTER USER`, `GRANT ... TO USER`) and a separate **login name** (used to authenticate). They can differ.
- Unquoted identifiers are uppercased. Quoted identifiers are case-sensitive. If `CURRENT_USER()` returns lowercase, quote it.
- **Key rotation:** a user has two slots, `RSA_PUBLIC_KEY` and `RSA_PUBLIC_KEY_2`. Set the new key in the free slot, switch clients over, then `UNSET` the old one.
- **Renaming users:** `ALTER USER ... RENAME TO` and `SET LOGIN_NAME` exist. With Google sign-in, though, Snowflake has to match the Google email to a user, and changing the login name could lock you out of Snowsight. We didn't rename.

## 5. "JWT token is invalid"
The connection uses:
```toml
authenticator = "SNOWFLAKE_JWT"
private_key_file = "${SNOWFLAKE_PRIVATE_KEY_FILE}"
```
```
390144 (28000): JWT token is invalid.
```
**Cause:** `SNOWFLAKE_USER` was set to the user name. The key-pair login is checked against the **login name**.

**Fix:** set `SNOWFLAKE_USER=<login_name>` in `.env`, then reload the project and test:
```bash
source scripts/use-project.sh 02-snow-hands-on-labs/b01-data-warehousing
snow connection test    # Status OK, Role SYSADMIN
```
**Lesson:** use the user name in SQL and the login name in the client connection.

Other common causes of this error: the clock is out of sync (JWTs expire quickly), the wrong account identifier, or a public key that doesn't match the private key (compare fingerprints, section 4).

## 6. Create DEMO_DB and transfer ownership
`sql/02_demo_db.sql`:
```sql
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS DEMO_DB;
GRANT OWNERSHIP ON DATABASE DEMO_DB TO ROLE SYSADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON ALL SCHEMAS IN DATABASE DEMO_DB TO ROLE SYSADMIN COPY CURRENT GRANTS;
USE ROLE SYSADMIN;
SHOW DATABASES LIKE 'DEMO_DB';
SHOW SCHEMAS IN DATABASE DEMO_DB;
```
```bash
snow sql -f projects/02-snow-hands-on-labs/b01-data-warehousing/sql/02_demo_db.sql
```
**Result:** the `owner` column shows `SYSADMIN` for `DEMO_DB` and for `DEMO_DB.PUBLIC`.

**Reasoning:**
- **Ownership follows the creating role.** Created as ACCOUNTADMIN, the database sits outside the SYSADMIN hierarchy, so SYSADMIN and any custom roles under it can't manage it. Snowflake recommends that SYSADMIN, or roles granted to it, own databases and warehouses.
- **The `PUBLIC` schema** is created automatically with the database, and ACCOUNTADMIN owns it too. Its ownership needs its own transfer. `INFORMATION_SCHEMA` is system-managed and has no owner.
- **`COPY CURRENT GRANTS`** keeps the existing grants on the object. Without it, Snowflake rejects the transfer if grants exist, or you must use `REVOKE CURRENT GRANTS` to drop them.
- **ACCOUNTADMIN in the script only.** The connection's default role is SYSADMIN, and the script switches up for the one statement that needs it.
- **`IF NOT EXISTS`** lets the script be rerun safely.
- **No warehouse needed.** `CREATE DATABASE`, `GRANT` and `SHOW` are metadata operations handled by the cloud services layer, so they use no warehouse credits.

## Next
Loading and querying data needs a warehouse. Add a dedicated one: XSMALL, `AUTO_SUSPEND=60`, `AUTO_RESUME=TRUE`, with a resource monitor, and never `COMPUTE_WH`.
