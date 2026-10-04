-- One line per base table: schema.table|row count|checksum.
-- The checksum is the sum of a 60 bit hash of each row, so it does not depend on row order
-- and uses constant memory. It is not cryptographic. An empty table gives 0, never NULL.
-- Unlogged tables are skipped: they are not replicated, hold only ephemeral state (locks,
-- leader election), and reading one on a hot standby raises an error that aborts the query.
SELECT t.table_schema || '.' || t.table_name || '|' ||
  (xpath('/row/c/text()', query_to_xml(
    format('select count(*) as c from %I.%I', t.table_schema, t.table_name),
    false, true, '')))[1]::text || '|' ||
  (xpath('/row/h/text()', query_to_xml(
    format('select coalesce(sum((''x'' || substr(md5(x::text), 1, 15))::bit(60)::bigint::numeric), 0) as h from %I.%I x',
           t.table_schema, t.table_name),
    false, true, '')))[1]::text
FROM information_schema.tables t
WHERE t.table_type = 'BASE TABLE' AND t.table_schema NOT IN ('pg_catalog', 'information_schema')
  AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = t.table_schema AND c.relname = t.table_name AND c.relpersistence = 'u')
ORDER BY 1;
