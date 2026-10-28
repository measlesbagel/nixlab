# PostgreSQL and its backup

seladonia runs PostgreSQL 18 on `rpool/safe/postgres`. It creates the
databases and owners listed in `homelab.postgres.databases`. A nightly dump
writes `/var/backup/postgresql`, which restic then ships to RustFS.

## Sub-features

- `pg-up`: the server accepts connections over the local socket, and its version is 18.
- `pg-databases`: each `homelab.postgres.databases` entry exists, owned by the role of the same name.
- `pg-dump`: `postgresqlBackup` writes a non-empty compressed dump.

## How to get to it (user POV)

- `sudo -u postgres psql` on the host.
- `postgresqlBackup.timer` runs at 01:15, or an operator runs
  `systemctl start postgresqlBackup`.

## Driving it with nixlab-vm

Preconditions:

- The baseline is met.

Steps:

- **Server up.** Run `nixlab-vm exec -- 'sudo -u postgres psql -tAc "show server_version"'`.
  The version starts with `18.`, for example `18.6`.
- **Data on ZFS.** Run `nixlab-vm exec -- 'sudo -u postgres psql -tAc "show data_directory"; findmnt -no SOURCE -T /var/lib/postgresql'`.
  The data directory is `/var/lib/postgresql/18`, and its source is
  `rpool/safe/postgres`.
- **Declared databases.** Run `nixlab-vm exec -- 'sudo -u postgres psql -tAc "select datname, pg_get_userbyid(datdba) from pg_database where not datistemplate"'`.
  Each `homelab.postgres.databases` name appears, owned by itself.
- **Write, then dump.** Pass `nixlab-vm exec --` this multi-line script, single-quoted:
  ```sh
  sudo -u postgres psql <<'SQL'
  create table verify(x text);
  insert into verify values ('nixlab-verify');
  SQL
  systemctl start postgresqlBackup.service; systemctl show -p Result --value postgresqlBackup.service
  ```
  The output is `CREATE TABLE`, then `INSERT 0 1`, then `success`.
- **Second view.** Run `nixlab-vm exec -- 'ls -l /var/backup/postgresql; zcat /var/backup/postgresql/all.sql.gz | grep -c nixlab-verify'`.
  The dump exists, and the count is at least 1.

## Gotchas

- On `main`, `homelab.postgres.databases` may be empty. Then `pg-databases`
  only shows `postgres`, which is correct rather than a failure.
- The dump is `/var/backup/postgresql/all.sql.gz`, mode 0600 and owned by
  postgres, so read it as root.
- Inside a double-quoted shell string, `$$` is the shell's PID. Use the
  heredoc above for SQL literals.
- The restic upload to RustFS needs the network and secrets, so it cannot be
  verified here.
