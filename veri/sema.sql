-- Optik veritabanı şeması (SQLite)
-- Para: INTEGER kuruş. Tarih ve saat: UTC ISO 8601 metin. Yalnızca tarih: YYYY-MM-DD.
-- Kimlikler: metin UUID (ileride senkron için).

PRAGMA foreign_keys = ON;

-- ---------- Kişiler ----------
CREATE TABLE people (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  relation        TEXT,                    -- 'arkadas', 'aile', 'proje ortagi', 'danisman', 'partner' ...
  is_partner      INTEGER NOT NULL DEFAULT 0,
  notes           TEXT,
  last_contact_at TEXT,
  created_at      TEXT NOT NULL
);

-- ---------- Müşteriler, teklifler, siparişler ----------
CREATE TABLE clients (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  contact_name  TEXT,
  contact_phone TEXT,
  contact_email TEXT,
  notes         TEXT,
  last_contact_at TEXT,
  created_at    TEXT NOT NULL
);

CREATE TABLE quotes (
  id           TEXT PRIMARY KEY,
  client_id    TEXT NOT NULL REFERENCES clients(id),
  title        TEXT NOT NULL,
  amount       INTEGER NOT NULL,          -- kuruş
  currency     TEXT NOT NULL DEFAULT 'TRY',
  status       TEXT NOT NULL CHECK (status IN ('draft','sent','accepted','rejected')),
  sent_at      TEXT,
  follow_up_on TEXT,                      -- YYYY-MM-DD
  decided_at   TEXT,
  reject_reason TEXT,
  file_path    TEXT,
  created_at   TEXT NOT NULL
);

CREATE TABLE orders (
  id           TEXT PRIMARY KEY,
  client_id    TEXT NOT NULL REFERENCES clients(id),
  quote_id     TEXT REFERENCES quotes(id),
  title        TEXT NOT NULL,
  description  TEXT,
  total_amount INTEGER NOT NULL,          -- kuruş
  currency     TEXT NOT NULL DEFAULT 'TRY',
  upfront_amount INTEGER NOT NULL DEFAULT 0, -- sipariş açılırken alınan kapora (kuruş)
  due_on       TEXT,                      -- son teslim, YYYY-MM-DD
  closed_at    TEXT,
  created_at   TEXT NOT NULL
);

CREATE TABLE order_milestones (
  id             TEXT PRIMARY KEY,
  order_id       TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  position       INTEGER NOT NULL,
  title          TEXT NOT NULL,
  due_on         TEXT,                    -- YYYY-MM-DD
  done_at        TEXT,
  payment_amount INTEGER NOT NULL DEFAULT 0, -- bu adım bitince doğan tahsilat (kuruş)
  UNIQUE (order_id, position)
);

CREATE TABLE order_payments (
  id           TEXT PRIMARY KEY,
  order_id     TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  milestone_id TEXT REFERENCES order_milestones(id),
  amount       INTEGER NOT NULL,          -- kuruş
  received_at  TEXT NOT NULL,
  note         TEXT
);

CREATE TABLE order_costs (
  id        TEXT PRIMARY KEY,
  order_id  TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  title     TEXT NOT NULL,
  amount    INTEGER NOT NULL,             -- kuruş
  spent_on  TEXT NOT NULL
);

CREATE TABLE order_files (
  id        TEXT PRIMARY KEY,
  order_id  TEXT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  kind      TEXT NOT NULL CHECK (kind IN ('quote','contract','invoice','other')),
  title     TEXT NOT NULL,
  path_or_url TEXT NOT NULL
);

-- ---------- Projeler ----------
CREATE TABLE projects (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  notes      TEXT,
  closed_at  TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE project_steps (
  id         TEXT PRIMARY KEY,
  project_id TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
  position   INTEGER NOT NULL,
  title      TEXT NOT NULL,
  done_at    TEXT,
  UNIQUE (project_id, position)
);

-- ---------- Dersler ----------
CREATE TABLE courses (
  id    TEXT PRIMARY KEY,
  name  TEXT NOT NULL,
  term  TEXT
);

CREATE TABLE course_slots (
  id        TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  weekday   INTEGER NOT NULL CHECK (weekday BETWEEN 1 AND 7), -- 1 = Pazartesi
  starts    TEXT NOT NULL,              -- HH:MM yerel saat
  ends      TEXT,
  location  TEXT
);

-- ---------- Takvim ve görevler ----------
CREATE TABLE events (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  kind        TEXT NOT NULL CHECK (kind IN ('meeting','class','personal','work')),
  starts_at   TEXT NOT NULL,
  ends_at     TEXT,
  location    TEXT,
  person_id   TEXT REFERENCES people(id),
  client_id   TEXT REFERENCES clients(id),
  project_id  TEXT REFERENCES projects(id),
  order_id    TEXT REFERENCES orders(id),
  course_id   TEXT REFERENCES courses(id),
  notes       TEXT,
  source      TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','voice','calendar','rule')),
  external_id TEXT,
  created_at  TEXT NOT NULL
);
CREATE INDEX events_starts ON events(starts_at);

CREATE TABLE tasks (
  id         TEXT PRIMARY KEY,
  title      TEXT NOT NULL,
  kind       TEXT NOT NULL CHECK (kind IN ('todo','assignment','exam','bill','plan')),
  due_at     TEXT,
  done_at    TEXT,
  person_id  TEXT REFERENCES people(id),
  project_id TEXT REFERENCES projects(id),
  order_id   TEXT REFERENCES orders(id),
  course_id  TEXT REFERENCES courses(id),
  notes      TEXT,
  created_at TEXT NOT NULL
);
CREATE INDEX tasks_due ON tasks(due_at) WHERE done_at IS NULL;

-- ---------- Para ----------
CREATE TABLE budget_categories (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL UNIQUE,
  monthly_limit INTEGER NOT NULL,        -- kuruş
  position      INTEGER NOT NULL
);

CREATE TABLE expenses (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  amount       INTEGER NOT NULL,         -- kuruş
  category_id  TEXT NOT NULL REFERENCES budget_categories(id),
  spent_at     TEXT NOT NULL,
  source       TEXT NOT NULL DEFAULT 'manual' CHECK (source IN ('manual','voice','receipt')),
  receipt_path TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX expenses_spent ON expenses(spent_at);

CREATE TABLE planned_cash (                -- nakit akışı takvimi için elle girilen beklenen giriş ve çıkışlar
  id       TEXT PRIMARY KEY,
  title    TEXT NOT NULL,
  amount   INTEGER NOT NULL,             -- kuruş, giriş artı, çıkış eksi
  scope    TEXT NOT NULL CHECK (scope IN ('personal','business')),
  due_on   TEXT NOT NULL,
  done_at  TEXT
);

-- ---------- İlişki ----------
CREATE TABLE important_dates (
  id            TEXT PRIMARY KEY,
  title         TEXT NOT NULL,
  month         INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  day           INTEGER NOT NULL CHECK (day BETWEEN 1 AND 31),
  year          INTEGER,                  -- yıllık tekrar ediyorsa boş
  person_id     TEXT REFERENCES people(id)
);

CREATE TABLE together_log (
  id      TEXT PRIMARY KEY,
  day     TEXT NOT NULL,                  -- YYYY-MM-DD
  note    TEXT
);

-- ---------- Notlar ve arama ----------
CREATE TABLE notes (
  id         TEXT PRIMARY KEY,
  body       TEXT NOT NULL,
  person_id  TEXT REFERENCES people(id),
  client_id  TEXT REFERENCES clients(id),
  project_id TEXT REFERENCES projects(id),
  order_id   TEXT REFERENCES orders(id),
  locked     INTEGER NOT NULL DEFAULT 0,  -- 1 ise kilitli bölümlere ait, kilitliyken LLM bağlamına girmez
  created_at TEXT NOT NULL
);

CREATE VIRTUAL TABLE notes_fts USING fts5(
  body, content='notes', content_rowid='rowid', tokenize = 'unicode61 remove_diacritics 2'
);
CREATE TRIGGER notes_ai AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, body) VALUES (new.rowid, new.body);
END;
CREATE TRIGGER notes_ad AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
END;
CREATE TRIGGER notes_au AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, body) VALUES ('delete', old.rowid, old.body);
  INSERT INTO notes_fts(rowid, body) VALUES (new.rowid, new.body);
END;

-- ---------- Hatırlatıcılar ve öneriler ----------
CREATE TABLE reminders (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  fire_at      TEXT NOT NULL,
  repeat_rule  TEXT,                      -- boş ya da 'daily' | 'weekly' | 'monthly' | 'yearly'
  source_type  TEXT,                      -- 'event' | 'task' | 'milestone' | 'quote' | 'date' | 'manual'
  source_id    TEXT,
  delivered_at TEXT,
  dismissed_at TEXT,
  created_at   TEXT NOT NULL
);
CREATE INDEX reminders_fire ON reminders(fire_at) WHERE delivered_at IS NULL;

CREATE TABLE suggestions (
  id          TEXT PRIMARY KEY,
  rule        TEXT NOT NULL,              -- kural adı, örn. 'budget_80', 'person_3w', 'milestone_due'
  subject_id  TEXT,                       -- kuralın ilgili olduğu kayıt
  body        TEXT NOT NULL,              -- kullanıcıya gösterilen cümle
  action_json TEXT,                       -- kabul edilince çalışacak araç çağrısı
  created_at  TEXT NOT NULL,
  resolved_at TEXT,
  resolution  TEXT CHECK (resolution IN ('accepted','skipped','expired'))
);

-- ---------- Konuşma kaydı, değişiklik günlüğü, ayarlar ----------
CREATE TABLE conversation_log (
  id              TEXT PRIMARY KEY,
  started_at      TEXT NOT NULL,
  trigger         TEXT NOT NULL CHECK (trigger IN ('wake_word','hotkey','click','proactive','text')),
  transcript      TEXT,
  response        TEXT,
  model           TEXT,
  tool_calls_json TEXT,
  latency_ms_json TEXT,                   -- wake_to_island, wake_to_efendim, speech_end_to_transcript, transcript_to_first_token, first_token_to_first_audio, total
  error           TEXT
);

CREATE TABLE change_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  at         TEXT NOT NULL,
  table_name TEXT NOT NULL,
  row_id     TEXT NOT NULL,
  op         TEXT NOT NULL CHECK (op IN ('insert','update','delete')),
  before_json TEXT,
  after_json  TEXT,
  source     TEXT NOT NULL CHECK (source IN ('voice','manual','rule','import','undo')),
  conversation_id TEXT REFERENCES conversation_log(id)
);

CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- ---------- Görünümler ----------
-- Sipariş başına alınan ve kalan tutar
CREATE VIEW order_balance AS
SELECT o.id AS order_id,
       o.total_amount,
       o.upfront_amount + COALESCE((SELECT SUM(p.amount) FROM order_payments p WHERE p.order_id = o.id), 0) AS received_amount,
       o.total_amount - o.upfront_amount - COALESCE((SELECT SUM(p.amount) FROM order_payments p WHERE p.order_id = o.id), 0) AS remaining_amount,
       COALESCE((SELECT SUM(c.amount) FROM order_costs c WHERE c.order_id = o.id), 0) AS cost_amount
FROM orders o;

-- Vadesi gelmiş ama alınmamış tahsilatlar (kilometre taşı bitti, ödemesi yok)
CREATE VIEW due_payments AS
SELECT m.order_id, m.id AS milestone_id, m.title, m.payment_amount, m.done_at
FROM order_milestones m
WHERE m.done_at IS NOT NULL
  AND m.payment_amount > 0
  AND NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.milestone_id = m.id);
