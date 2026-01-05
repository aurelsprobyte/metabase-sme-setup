-- demo/init/01_seed.sql
-- Seed dáta pre demo_data_db (spustí sa len pri prvom vytvorení databázy/volume)

BEGIN;

CREATE SCHEMA IF NOT EXISTS public;

-- Zákazníci
CREATE TABLE IF NOT EXISTS customers (
  id            BIGSERIAL PRIMARY KEY,
  name          TEXT NOT NULL,
  industry      TEXT NOT NULL,
  city          TEXT NOT NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Faktúry (vydané)
CREATE TABLE IF NOT EXISTS invoices (
  id            BIGSERIAL PRIMARY KEY,
  customer_id   BIGINT NOT NULL REFERENCES customers(id),
  invoice_no    TEXT NOT NULL UNIQUE,
  issued_date   DATE NOT NULL,
  due_date      DATE NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('draft','sent','paid','overdue')),
  currency      TEXT NOT NULL DEFAULT 'EUR',
  total_amount  NUMERIC(12,2) NOT NULL,
  vat_amount    NUMERIC(12,2) NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Náklady
CREATE TABLE IF NOT EXISTS expenses (
  id            BIGSERIAL PRIMARY KEY,
  expense_date  DATE NOT NULL,
  category      TEXT NOT NULL,
  vendor        TEXT NOT NULL,
  amount        NUMERIC(12,2) NOT NULL,
  currency      TEXT NOT NULL DEFAULT 'EUR',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Jednoduché KPI view
CREATE OR REPLACE VIEW kpi_monthly_cashflow AS
SELECT
  date_trunc('month', d)::date AS month,
  COALESCE(SUM(i.total_amount) FILTER (WHERE i.status = 'paid'), 0) AS income_paid,
  COALESCE(SUM(e.amount), 0) AS expenses,
  COALESCE(SUM(i.total_amount) FILTER (WHERE i.status = 'paid'), 0) - COALESCE(SUM(e.amount), 0) AS net_cashflow
FROM generate_series(date_trunc('month', now()) - interval '11 months', date_trunc('month', now()), interval '1 month') AS d
LEFT JOIN invoices i ON date_trunc('month', i.issued_date) = date_trunc('month', d)
LEFT JOIN expenses e ON date_trunc('month', e.expense_date) = date_trunc('month', d)
GROUP BY 1
ORDER BY 1;

-- Seed: zákazníci
INSERT INTO customers (name, industry, city, is_active, created_at) VALUES
('Prva firma s.r.o.', 'Manufacturing', 'Tvrdošín', true, now() - interval '420 days'),
('Druha firma s r.o.', 'Woodworking', 'Námestovo', true, now() - interval '300 days'),
('Tretia firma s.r.o.', 'Construction', 'Ružomberok', true, now() - interval '260 days'),
('Stvrta firma a.s.', 'Logistics', 'Žilina', true, now() - interval '220 days'),
('Piata firma s.r.o.', 'Services', 'Poprad', true, now() - interval '180 days')
ON CONFLICT DO NOTHING;

-- Seed: faktúry za posledných ~10 mesiacov
WITH months AS (
  SELECT (date_trunc('month', now()) - (n || ' months')::interval)::date AS m
  FROM generate_series(0, 9) AS n
),
cust AS (
  SELECT id, row_number() OVER (ORDER BY id) AS rn FROM customers
),
gen AS (
  SELECT
    c.id AS customer_id,
    m.m AS issued_date,
    (m.m + interval '14 days')::date AS due_date,
    CASE
      WHEN m.m < (date_trunc('month', now()) - interval '2 months') THEN 'paid'
      WHEN m.m = (date_trunc('month', now()) - interval '1 month') THEN 'sent'
      ELSE 'draft'
    END AS status,
    -- jednoduché sumy
    (900 + (c.rn * 120) + (extract(month from m.m)::int * 35))::numeric(12,2) AS total_amount
  FROM months m
  JOIN cust c ON c.rn <= 5
)
INSERT INTO invoices (customer_id, invoice_no, issued_date, due_date, status, currency, total_amount, vat_amount, created_at)
SELECT
  g.customer_id,
  'INV-' || to_char(g.issued_date, 'YYYYMM') || '-' || lpad(g.customer_id::text, 3, '0') AS invoice_no,
  g.issued_date,
  g.due_date,
  g.status,
  'EUR',
  g.total_amount,
  round(g.total_amount * 0.20, 2) AS vat_amount,
  (g.issued_date + interval '1 day')::timestamptz
FROM gen g
ON CONFLICT DO NOTHING;

-- Seed: náklady (mesačne + pár kategórií)
WITH months AS (
  SELECT (date_trunc('month', now()) - (n || ' months')::interval)::date AS m
  FROM generate_series(0, 11) AS n
),
cats AS (
  SELECT * FROM (VALUES
    ('Hosting', 'VPS Provider'),
    ('Energy', 'Utility Company'),
    ('Software', 'SaaS Tools'),
    ('Office', 'Office Supplies'),
    ('Accounting', 'Accounting Partner')
  ) AS t(category, vendor)
)
INSERT INTO expenses (expense_date, category, vendor, amount, currency, created_at)
SELECT
  (m.m + interval '5 days')::date AS expense_date,
  c.category,
  c.vendor,
  round((120 + (extract(month from m.m)::int * 7) + (random()*80))::numeric, 2) AS amount,
  'EUR',
  (m.m + interval '5 days')::timestamptz
FROM months m
CROSS JOIN cats c;

COMMIT;
