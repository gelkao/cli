CREATE TABLE raw_invoices (
  grouping     TEXT,
  product      TEXT,
  description  TEXT,
  reference    TEXT,
  quantity     TEXT,
  from_date    TEXT,
  until_date   TEXT,
  condition    TEXT,
  unit         TEXT,
  external_id  TEXT,
  price        TEXT,
  total        TEXT
);

CREATE TABLE prices (
  type           TEXT,
  price_group    TEXT,   -- eu | usa | sin  (one price per Hetzner location group)
  currency       TEXT,
  effective_from TEXT,
  price_hourly   REAL,
  price_monthly  REAL
);

CREATE INDEX prices_lookup ON prices (type, currency, price_group, effective_from);

CREATE TABLE server_types (
  type    TEXT,
  vcpu    INTEGER,
  ram_gb  INTEGER
);
