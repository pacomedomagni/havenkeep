-- Migration 013: Newsletter subscribers table
-- Stores email addresses collected from the marketing site newsletter signup form.

CREATE TABLE IF NOT EXISTS newsletter_subscribers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) NOT NULL,
  subscribed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  unsubscribed_at TIMESTAMPTZ,
  ip_address INET,
  source VARCHAR(50) DEFAULT 'blog',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Prevent duplicate active subscriptions for the same email
  CONSTRAINT uq_newsletter_email UNIQUE (email)
);

CREATE INDEX idx_newsletter_subscribers_email ON newsletter_subscribers(email);
CREATE INDEX idx_newsletter_subscribers_subscribed_at ON newsletter_subscribers(subscribed_at DESC);

COMMENT ON TABLE newsletter_subscribers IS 'Email addresses collected from the marketing site newsletter signup';
