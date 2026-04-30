-- Migration 087: promote webhook_events.id from int4 SERIAL to bigint.
--
-- Audit H-D5: webhook_events.id was int4 SERIAL. Mig 042 mentioned
-- DB024 ("rename SERIAL primary keys on high-volume tables to BIGSERIAL")
-- but never actually did it for webhook_events. At 2 events/sec
-- sustained the sequence runs out in under 30 years; combined with no
-- cleanup wired (already addressed by the daily cron in index.ts),
-- the table grows unbounded long before then.
--
-- Promote both the column and its sequence so existing primary-key
-- values are preserved and new inserts pull from a 64-bit space.

ALTER SEQUENCE webhook_events_id_seq AS bigint;
ALTER TABLE webhook_events ALTER COLUMN id TYPE bigint USING id::bigint;

DO $$
BEGIN
  RAISE NOTICE 'Migration 087 complete: webhook_events.id promoted to bigint (H-D5)';
END $$;
