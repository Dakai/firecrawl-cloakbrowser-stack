CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

CREATE SCHEMA IF NOT EXISTS nuq;

-- ─── Enum type used for all queue statuses ────────────────────────────────────
CREATE TYPE nuq.job_status AS ENUM (
  'queued',
  'active',
  'completed',
  'failed',
  'delayed'
);

-- ─── Core crawl group ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuq.group_crawl (
  id          uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  name        TEXT,
  owner_id    TEXT,
  status      nuq.job_status NOT NULL DEFAULT 'queued',
  created_at  TIMESTAMP      NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMP,
  expires_at  TIMESTAMP
);

-- ─── Scrape queue ─────────────────────────────────────────────────────────────
-- Columns derived from actual RETURNING clause in nuq.js:
-- id, status, created_at, priority, data, finished_at, listen_channel_id,
-- returnvalue, failedreason, lock, owner_id, group_id
CREATE TABLE IF NOT EXISTS nuq.queue_scrape (
  id                uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid           REFERENCES nuq.group_crawl(id) ON DELETE CASCADE,
  owner_id          TEXT,
  status            nuq.job_status NOT NULL DEFAULT 'queued',
  priority          INTEGER        NOT NULL DEFAULT 0,
  data              JSONB,
  returnvalue       JSONB,
  failedreason      TEXT,
  listen_channel_id TEXT,
  lock              uuid,
  locked_at         TIMESTAMP,
  created_at        TIMESTAMP      NOT NULL DEFAULT NOW(),
  finished_at       TIMESTAMP
);

-- ─── Crawl-finished queue ─────────────────────────────────────────────────────
-- Same shape as queue_scrape — consumed by crawlFinishWorker
CREATE TABLE IF NOT EXISTS nuq.queue_crawl_finished (
  id                uuid           PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id          uuid           REFERENCES nuq.group_crawl(id) ON DELETE CASCADE,
  owner_id          TEXT,
  status            nuq.job_status NOT NULL DEFAULT 'queued',
  priority          INTEGER        NOT NULL DEFAULT 0,
  data              JSONB,
  returnvalue       JSONB,
  failedreason      TEXT,
  listen_channel_id TEXT,
  lock              uuid,
  locked_at         TIMESTAMP,
  created_at        TIMESTAMP      NOT NULL DEFAULT NOW(),
  finished_at       TIMESTAMP
);

-- ─── Scrape backlog (overflow / retry holding area) ───────────────────────────
CREATE TABLE IF NOT EXISTS nuq.queue_scrape_backlog (
  id          uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id    uuid      REFERENCES nuq.group_crawl(id) ON DELETE CASCADE,
  owner_id    TEXT,
  data        JSONB,
  retry_count INTEGER   NOT NULL DEFAULT 0,
  created_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ─── Group concurrency tracker ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuq.queue_scrape_group_concurrency (
  id                  uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id            uuid      REFERENCES nuq.group_crawl(id) ON DELETE CASCADE,
  current_concurrency INTEGER   NOT NULL DEFAULT 0,
  max_concurrency     INTEGER   NOT NULL DEFAULT 1,
  updated_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ─── Indexes ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_qs_status_priority  ON nuq.queue_scrape(status, priority ASC, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_qs_group_id         ON nuq.queue_scrape(group_id);
CREATE INDEX IF NOT EXISTS idx_qcf_status_priority ON nuq.queue_crawl_finished(status, priority ASC, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_qcf_group_id        ON nuq.queue_crawl_finished(group_id);
CREATE INDEX IF NOT EXISTS idx_gc_status           ON nuq.group_crawl(status);
CREATE INDEX IF NOT EXISTS idx_gc_expires          ON nuq.group_crawl(expires_at);

-- ─── pg_cron: purge expired groups hourly ────────────────────────────────────
SELECT cron.schedule(
  'expire-group-crawl',
  '0 * * * *',
  $$DELETE FROM nuq.group_crawl WHERE expires_at IS NOT NULL AND expires_at < NOW()$$
);
