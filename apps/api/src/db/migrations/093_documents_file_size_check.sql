-- Migration 093: non-negative CHECK on documents.file_size.
--
-- Audit M-NEW-5: documents.file_size BIGINT had no non-negative
-- constraint. The Joi validator caps it on inbound writes, but a
-- buggy multer middleware (or a future direct DB write) could land
-- a negative value. The pattern in mig 070 ("if Joi validates it,
-- the DB enforces it too") gets every other field but missed
-- file_size.

ALTER TABLE documents
  DROP CONSTRAINT IF EXISTS chk_documents_file_size_nonneg;

ALTER TABLE documents
  ADD CONSTRAINT chk_documents_file_size_nonneg
  CHECK (file_size >= 0);

DO $$
BEGIN
  RAISE NOTICE 'Migration 093 complete: documents.file_size non-negative CHECK added (M-NEW-5)';
END $$;
