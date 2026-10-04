# verify.sh checked against live systems

Read-only, 2026-10-04.

- **Checksum query path (2026-10-04T05:44Z).** `verify.sh --checks compare --kind database --namespace ente --old-pod ente-db-1
  --new-pod ente-db-1 --db ente` ran `kubectl exec … -i -- psql -d ente -At -f -` with `table-checksums.sql` against the
  `ente-db` primary: `db=ente tables=81`, `verdict=verified`, 3.6 s. It compares a pod with itself, so it proves the exec path
  and that `psql` connects as the pod's user, not that a difference is detected: that is covered by `tests/sql.bats` against a
  real throwaway Postgres.
- **Encryption check (2026-10-04T05:27Z).** Run through a root debug pod with `--node-exec` against a throwaway encrypted and
  plain volume: `verdict=verified` and `verdict=failed` as expected. See `storage.md`.
- **No-call check.** Ran against the live SFU pod several times (`calls=1`, then `calls=3`): reads `livekit_participant_total`
  through a port-forward to each SFU pod found by label.

Not yet checked live: the Matrix functional check (needs the `verify-bot` token, T016), the backup check (needs a backup,
Phase 3), and `destroy-old-volume.sh --execute` (T059 proves it on a throwaway volume).
