-- Migration 079: convert items.product_image_url, users.avatar_url, and
--   documents.file_url from full public URLs to MinIO object keys (S-CR-02).
--
-- Audit: pre-S-CR-02 the API persisted permanent public-read URLs into
--   these columns and returned them to clients. A leaked URL (referrer
--   header, screenshot, support inbox, log forwarding) gave indefinite
--   access to a private file with no rotation. The fix is to:
--     1. Bucket policy: private (no public-read).
--     2. DB columns: hold object KEYS only, not URLs.
--     3. Read paths: mint short-lived presigned URLs at response time.
--   This migration handles step 2 — strip the URL prefix from any row
--   that already carries a URL, leaving only the object key.
--
-- The strip is shape-agnostic: anything that parses as `<protocol>://
--   <host>[:port]/<bucket>/<key>` collapses to `<key>`. Anything that
--   doesn't parse (already a key, or NULL/empty) is left as-is.
--
-- Idempotent: re-running is a no-op because the regex only matches rows
-- that still have the URL prefix.

-- ── items.product_image_url ───────────────────────────────────────────
UPDATE items
SET product_image_url = regexp_replace(
      product_image_url,
      -- Match: scheme://host[:port]/bucket/<rest>
      '^https?://[^/]+/[^/]+/',
      ''
    )
WHERE product_image_url IS NOT NULL
  AND product_image_url ~ '^https?://';

-- ── users.avatar_url ──────────────────────────────────────────────────
UPDATE users
SET avatar_url = regexp_replace(
      avatar_url,
      '^https?://[^/]+/[^/]+/',
      ''
    )
WHERE avatar_url IS NOT NULL
  AND avatar_url ~ '^https?://';

-- ── documents.file_url ───────────────────────────────────────────────
-- documents stores the full URL in `file_url` historically, but the
-- canonical key lives in `object_key` (added in mig 050). The value in
-- `file_url` should mirror what we stripped above; if the column still
-- exists, strip it too.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'documents' AND column_name = 'file_url'
  ) THEN
    EXECUTE $sql$
      UPDATE documents
      SET file_url = regexp_replace(
            file_url,
            '^https?://[^/]+/[^/]+/',
            ''
          )
      WHERE file_url IS NOT NULL
        AND file_url ~ '^https?://';
    $sql$;
  END IF;
END
$$;

COMMENT ON COLUMN items.product_image_url IS
  'MinIO object key (post-S-CR-02). Mint a presigned URL via presignedUrlForKey() at response time; never store a URL.';
COMMENT ON COLUMN users.avatar_url IS
  'MinIO object key (post-S-CR-02). Mint a presigned URL via presignedUrlForKey() at response time; never store a URL.';
