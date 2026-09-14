#!/usr/bin/env bats

setup() {
  # shellcheck source=../lib.sh
  source "$BATS_TEST_DIRNAME/../lib.sh"
  load fixtures
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "invoice_csv_url builds the CSV download URL with cn" {
  run invoice_csv_url 00000000-0000-0000-0000-000000000000 K0000000000
  [ "$status" -eq 0 ]
  [ "$output" = "https://usage.hetzner.com/00000000-0000-0000-0000-000000000000?csv&cn=K0000000000" ]
}

@test "month_of_csv extracts YYYY-MM from the first ISO date" {
  f="$BATS_TEST_TMPDIR/a.csv"
  printf 'grouping,from,total\nServer,2025-03-14,1.00\n' > "$f"
  run month_of_csv "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "2025-03" ]
}

@test "month_of_csv is empty when there is no date" {
  f="$BATS_TEST_TMPDIR/b.csv"
  printf 'no dates in here\n' > "$f"
  run month_of_csv "$f"
  [ "$output" = "" ]
}

@test "month_of_csv extracts YYYY-MM from a German DD.MM.YYYY date" {
  f="$BATS_TEST_TMPDIR/de.csv"
  printf 'grouping,from,total\nServer,01.06.2026,1.00\n' > "$f"
  run month_of_csv "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "2026-06" ]
}

@test "extract_uuids pulls UUIDs out of invoice HTML" {
  f="$BATS_TEST_TMPDIR/page.html"
  cat > "$f" <<'HTML'
<a href="https://usage.hetzner.com/11111111-2222-3333-4444-555555555555">detail</a>
<a href="https://usage.hetzner.com/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee?csv">csv</a>
<a href="/invoice/089000837082/pdf">old format, ignored</a>
HTML
  run extract_uuids "$f"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "extract_cn pulls the customer number out of invoice HTML" {
  f="$BATS_TEST_TMPDIR/page.html"
  cat > "$f" <<'HTML'
<span>Some Company Ltd</span> <td>K1234567890</td>
<a href="https://usage.hetzner.com/11111111-2222-3333-4444-555555555555">detail</a>
HTML
  run extract_cn "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "K1234567890" ]
}

@test "extract_cn ignores K-tokens that are not 10 digits" {
  f="$BATS_TEST_TMPDIR/noise.html"
  printf '<img src="/assets/images/info-dark-j6AMhK7.svg"/><small>K1234567890</small>\n' > "$f"
  run extract_cn "$f"
  [ "$status" -eq 0 ]
  [ "$output" = "K1234567890" ]
}

@test "extract_cn refuses to guess when the input holds several customer numbers" {
  f="$BATS_TEST_TMPDIR/two.html"
  printf '<td>K1111111111</td><td>K2222222222</td>\n' > "$f"
  run extract_cn "$f"
  [ "$status" -ne 0 ]
  [[ "$output" == *"several customer numbers"* ]]
}

@test "list_invoices emits the customer number alongside the UUIDs" {
  f="$BATS_TEST_TMPDIR/page.html"
  cat > "$f" <<'HTML'
<td>K1234567890</td>
<a href="https://usage.hetzner.com/11111111-2222-3333-4444-555555555555">detail</a>
HTML
  run list_invoices "$f"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "K1234567890" ]
  [ "${lines[1]}" = "11111111-2222-3333-4444-555555555555" ]
}

@test "fetch_all errors when no customer number reaches it" {
  run bash -c "echo 11111111-2222-3333-4444-555555555555 | '$ROOT/gelkao' invoice fetch -d '$BATS_TEST_TMPDIR/nf'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no customer number on stdin"* ]]
}

# curl is stubbed as a tripwire: any invocation drops a marker file. The skip
# path must never reach it.
@test "fetch_one skips an already-present invoice WITHOUT touching the network" {
  out="$BATS_TEST_TMPDIR/out"; mkdir -p "$out"
  uuid=11111111-2222-3333-4444-555555555555
  : > "$out/K0000000000-2025-03-$uuid.csv"   # pretend it was downloaded earlier

  curl() { touch "$BATS_TEST_TMPDIR/curl_called"; return 1; }

  run fetch_one "$uuid" K0000000000 "$out"
  [ "$status" -eq 10 ]
  [[ "$output" == skip* ]]
  [ ! -e "$BATS_TEST_TMPDIR/curl_called" ]   # network was never touched
}

# Stub curl to emulate a successful download (-o <file>), and confirm the file
# is named <cn>-<YYYY-MM>-<uuid>.csv.
@test "fetch_one downloads and names the file <cn>-<YYYY-MM>-<uuid>.csv" {
  out="$BATS_TEST_TMPDIR/out2"; mkdir -p "$out"
  uuid=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

  curl() {
    local f=""
    while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { f="$2"; shift; }; shift; done
    printf 'grouping,from,total\nServer,2024-12-05,1.00\n' > "$f"
    return 0
  }

  run fetch_one "$uuid" K0000000000 "$out"
  [ "$status" -eq 0 ]
  [[ "$output" == ok* ]]
  [ -f "$out/K0000000000-2024-12-$uuid.csv" ]
}

@test "gelkao invoice -g is rejected for list and fetch" {
  run "$ROOT/gelkao" invoice list -g "Project prod"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid for list"* ]]

  run "$ROOT/gelkao" invoice fetch -g "Project prod"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid for fetch"* ]]
}

@test "gelkao invoice fetch -d <dir> looks in <dir> (skips a pre-seeded invoice, no network)" {
  d="$BATS_TEST_TMPDIR/f"; mkdir -p "$d"
  uuid=11111111-2222-3333-4444-555555555555
  invoice_csv "$d/K0000000000-2025-11-$uuid.csv"
  run bash -c "printf 'K0000000000\n%s\n' '$uuid' | '$ROOT/gelkao' invoice fetch -d '$d'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}

@test "gelkao invoice -h prints the usage instead of reading -h as a subcommand" {
  run "$ROOT/gelkao" invoice -h
  [ "$status" -eq 0 ]
  [[ "$output" = Usage:* ]]
}

@test "gelkao invoice -d is rejected for list" {
  run "$ROOT/gelkao" invoice list -d /tmp
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid for list"* ]]
}

@test "gelkao invoice -f is rejected for list and fetch" {
  run "$ROOT/gelkao" invoice list -f /tmp/x.db
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid for list"* ]]

  run "$ROOT/gelkao" invoice fetch -f /tmp/x.db
  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid for fetch"* ]]
}

@test "build_db fails when the data dir has no CSVs" {
  d="$BATS_TEST_TMPDIR/empty"; mkdir -p "$d"
  run build_db "$BATS_TEST_TMPDIR/e.db" "$ROOT" "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no invoice CSVs"* ]]
}

@test "build_db loads the tables, detects the group, and prices the cheaper same-spec type" {
  a="$BATS_TEST_TMPDIR/assets"; fixture_assets "$a"
  d="$BATS_TEST_TMPDIR/inv"; mkdir -p "$d"; cx33_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/f.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" 'SELECT count(*) FROM prices;')" -eq 3 ]
  [ "$(sqlite3 "$db" 'SELECT count(*) FROM server_types;')" -eq 2 ]
  [ "$(sqlite3 "$db" 'SELECT price_group FROM detected_group;')" = "eu" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f|%.2f', paid, optimal) FROM priced;")" = "4.99|3.79" ]
}

@test "build_db shows no phantom waste on a dedicated (ccx) line" {
  a="$BATS_TEST_TMPDIR/deda"; dedicated_assets "$a"
  d="$BATS_TEST_TMPDIR/dedi"; mkdir -p "$d"; dedicated_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/ded.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f|%.2f', paid, optimal) FROM priced;")" = "42.99|42.99" ]
}

@test "build_db still optimizes shared lines while zeroing dedicated ones in one invoice" {
  a="$BATS_TEST_TMPDIR/mixa"; dedicated_mixed_assets "$a"
  d="$BATS_TEST_TMPDIR/mixi"; mkdir -p "$d"; dedicated_mixed_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/mix.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE box='x1';")" = "3.79" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f|%.2f', paid, optimal) FROM priced WHERE box='d1';")" = "42.99|42.99" ]
}

@test "build_db zeroes both hourly and monthly dedicated lines" {
  a="$BATS_TEST_TMPDIR/hma"; dedicated_assets "$a"
  d="$BATS_TEST_TMPDIR/hmi"; mkdir -p "$d"; dedicated_hourly_monthly_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/hm.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" "SELECT count(*) FROM priced WHERE paid <> optimal;")" = "0" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE kind='hourly';")" = "16.44" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE kind='monthly';")" = "42.99" ]
}

@test "build_db audits a German-locale invoice identically to English (end-to-end)" {
  a="$BATS_TEST_TMPDIR/dea"; fixture_assets "$a"
  d="$BATS_TEST_TMPDIR/ded"; mkdir -p "$d"; cx33_invoice_de "$d/i.csv"
  db="$BATS_TEST_TMPDIR/de2.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" 'SELECT price_group FROM detected_group;')" = "eu" ]
  [ "$(sqlite3 "$db" "SELECT printf('%s|%s|%.2f|%.2f', month, kind, paid, optimal) FROM priced;")" = "2025-11|monthly|4.99|3.79" ]
}

@test "build_db audits a data dir mixing English and German invoices (per-row locale)" {
  a="$BATS_TEST_TMPDIR/mixa"; fixture_assets "$a"
  d="$BATS_TEST_TMPDIR/mixd"; mkdir -p "$d"
  cx33_invoice "$d/en.csv"
  write_invoice "$d/de.csv" <<CSV
"P","CX33 Cloud Server",,,"1,0000",01.12.2025,31.12.2025,,"Monate","b2",,"4,9900 €"
CSV
  db="$BATS_TEST_TMPDIR/mix.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" "SELECT printf('%s|%.2f', month, paid) FROM priced WHERE box='b1';")" = "2025-11|4.99" ]
  [ "$(sqlite3 "$db" "SELECT printf('%s|%.2f', month, paid) FROM priced WHERE box='b2';")" = "2025-12|4.99" ]
}

@test "build_db fails when a price asset is missing" {
  a="$BATS_TEST_TMPDIR/assets3"; fixture_assets "$a"; rm "$a/providers/hetzner/prices.csv"
  d="$BATS_TEST_TMPDIR/inv3"; mkdir -p "$d"; cx33_invoice "$d/i.csv"
  run build_db "$BATS_TEST_TMPDIR/f3.db" "$a" "$d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"prices.csv"* ]]
}

@test "build_db uses a live/ price override instead of the committed providers/ table" {
  a="$BATS_TEST_TMPDIR/assetsL"; fixture_assets "$a"
  mkdir -p "$a/live/hetzner"
  cat > "$a/live/hetzner/prices.csv" <<CSV
type,price_group,currency,effective_from,price_hourly,price_monthly
cx33,eu,eur,2025-10-01,0.0080,4.99
cax21,eu,eur,2025-10-01,0.0070,3.50
CSV
  cp "$a/providers/hetzner/server_types.csv" "$a/live/hetzner/server_types.csv"
  d="$BATS_TEST_TMPDIR/invL"; mkdir -p "$d"; cx33_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/fL.db"
  run build_db "$db" "$a" "$d"
  [ "$status" -eq 0 ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced;")" = "3.50" ]
}

@test "normalize.sql converts a German DD.MM.YYYY from_date to ISO" {
  db="$BATS_TEST_TMPDIR/de.db"
  sqlite3 "$db" < "$ROOT/schema.sql"
  sqlite3 "$db" "INSERT INTO raw_invoices (from_date) VALUES ('01.06.2026');"
  sqlite3 "$db" < "$ROOT/normalize.sql"
  [ "$(sqlite3 "$db" 'SELECT from_date FROM invoices;')" = "2026-06-01" ]
}

@test "normalize.sql parses total amounts robustly across locale and thousands separators" {
  db="$BATS_TEST_TMPDIR/amt.db"
  sqlite3 "$db" < "$ROOT/schema.sql"
  sqlite3 "$db" "INSERT INTO raw_invoices (external_id, from_date, total) VALUES
    ('a','01.06.2026','4,4900 €'),
    ('b','01.06.2026','1.036,49 €'),
    ('c','2026-06-01','€ 1,036.49'),
    ('d','2026-06-01','€ 157.3000');"
  sqlite3 "$db" < "$ROOT/normalize.sql"
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', total) FROM invoices WHERE external_id='a';")" = "4.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', total) FROM invoices WHERE external_id='b';")" = "1036.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', total) FROM invoices WHERE external_id='c';")" = "1036.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', total) FROM invoices WHERE external_id='d';")" = "157.30" ]
}

@test "normalize.sql parses quantity robustly across locale and thousands separators" {
  db="$BATS_TEST_TMPDIR/qty.db"
  sqlite3 "$db" < "$ROOT/schema.sql"
  sqlite3 "$db" "INSERT INTO raw_invoices (external_id, from_date, quantity) VALUES
    ('a','01.06.2026','1,5000'),
    ('b','01.06.2026','1.024,0000'),
    ('c','2026-06-01','1,024.0000'),
    ('d','2026-06-01','10.0000');"
  sqlite3 "$db" < "$ROOT/normalize.sql"
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', quantity) FROM invoices WHERE external_id='a';")" = "1.50" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', quantity) FROM invoices WHERE external_id='b';")" = "1024.00" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', quantity) FROM invoices WHERE external_id='c';")" = "1024.00" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', quantity) FROM invoices WHERE external_id='d';")" = "10.00" ]
}

@test "normalize.sql maps German unit words to English" {
  db="$BATS_TEST_TMPDIR/unit.db"
  sqlite3 "$db" < "$ROOT/schema.sql"
  sqlite3 "$db" "INSERT INTO raw_invoices (external_id, from_date, unit) VALUES
    ('a','01.06.2026','Stunden'),
    ('b','01.06.2026','Monate'),
    ('c','01.06.2026','TB-Stunden'),
    ('d','2026-06-01','Hours');"
  sqlite3 "$db" < "$ROOT/normalize.sql"
  [ "$(sqlite3 "$db" "SELECT unit FROM invoices WHERE external_id='a';")" = "Hours" ]
  [ "$(sqlite3 "$db" "SELECT unit FROM invoices WHERE external_id='b';")" = "Months" ]
  [ "$(sqlite3 "$db" "SELECT unit FROM invoices WHERE external_id='c';")" = "TB-Hours" ]
  [ "$(sqlite3 "$db" "SELECT unit FROM invoices WHERE external_id='d';")" = "Hours" ]
}

@test "an untouched box across the 15-Jun hike is scored month by month: its optimal rises 6.49 (Jun) to 8.49 (Jul) as the cheap alternative recedes" {
  a="$BATS_TEST_TMPDIR/uha"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/uhd"; mkdir -p "$d"; jun2026_untouched_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/uh.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE month='2026-06';")" = "6.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE month='2026-07';")" = "8.49" ]
}

@test "scoring 1: a box is priced against its cheaper same-spec at list, never borrowing another fleet box's locked rate" {
  a="$BATS_TEST_TMPDIR/tba"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/tbd"; mkdir -p "$d"; jun2026_two_box_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/tb.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE box='c1';")" = "8.49" ]
}

@test "scoring 2: optimal_locked holds the cheapest rate available since the box's first month, not the risen list" {
  a="$BATS_TEST_TMPDIR/lka"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/lkd"; mkdir -p "$d"; jun2026_untouched_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/lk.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-06';")" = "6.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-07';")" = "6.49" ]
}

@test "scoring 2: Alice keeps the cheap box she inherited when Bob scales it up, not the pricier market rate" {
  a="$BATS_TEST_TMPDIR/sua"; jun2026_scaleup_assets "$a"
  d="$BATS_TEST_TMPDIR/sud"; mkdir -p "$d"; jun2026_scaleup_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/su.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-05';")" = "4.99" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-06';")" = "4.99" ]
}

@test "scoring 2: a box with both hourly and monthly lines keeps units separate — no hourly rate leaks into the monthly lock" {
  a="$BATS_TEST_TMPDIR/mka"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/mkd"; mkdir -p "$d"; jun2026_mixed_kind_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/mk.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-06';")" = "6.49" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-05';")" = "2.50" ]
}

@test "an hourly line is priced against the cheapest same-spec hourly rate, not its own" {
  a="$BATS_TEST_TMPDIR/hpa"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/hpd"; mkdir -p "$d"; jun2026_mixed_kind_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/hp.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f|%.2f', paid, optimal) FROM priced WHERE kind='hourly';")" = "8.06|2.50" ]
}

@test "scoring 2: an hourly box's lock holds the cheapest rate from an earlier month across the hike, not the risen rate" {
  a="$BATS_TEST_TMPDIR/hla"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/hld"; mkdir -p "$d"; jun2026_hourly_lock_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/hl.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE box='b1' AND month='2026-07';")" = "2.50" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE box='b1' AND month='2026-07';")" = "3.26" ]
}

@test "scoring 2: the lock resets across a non-grandfathered hike (only 15-Jun-2026 grandfathers), so a pre-April rate is not carried past it" {
  a="$BATS_TEST_TMPDIR/gfa"; jun2026_reprice_assets "$a"
  d="$BATS_TEST_TMPDIR/gfd"; mkdir -p "$d"; jun2026_across_april_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/gf.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-03';")" = "4.99" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-05';")" = "6.49" ]
}

@test "scoring 2: resizing a box to a bigger spec resets the lock — a cheap small-box rate is not carried onto the bigger box" {
  a="$BATS_TEST_TMPDIR/rza"; jun2026_resize_assets "$a"
  d="$BATS_TEST_TMPDIR/rzd"; mkdir -p "$d"; jun2026_resize_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/rz.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-05';")" = "3.79" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal_locked) FROM priced WHERE month='2026-06';")" = "6.49" ]
}

@test "a lone post-15-Jun invoice still detects its price group from an old locked rate, so the box is priced against the cheaper type (no false 0%)" {
  a="$BATS_TEST_TMPDIR/pha"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/phd"; mkdir -p "$d"; jun2026_post_hike_only_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/ph.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT price_group FROM detected_group;")" = "eu" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced;")" = "8.49" ]
}

@test "a same-type box reacquired after the hike is optimal at the new price, not judged against the torn-down box's gone April rate" {
  a="$BATS_TEST_TMPDIR/ra"; jun2026_solo_assets "$a"
  d="$BATS_TEST_TMPDIR/rd"; mkdir -p "$d"; jun2026_reacquired_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/r.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced WHERE box='t2';")" = "22.08" ]
}

@test "an all-hourly fleet still detects its price group so a cheaper same-spec type is priced (no false 0% for short-lived boxes)" {
  skip "DKH-653: no monthly line -> detect_group empty -> cheaper same-spec type left unpriced; needs hourly-line voting"
  a="$BATS_TEST_TMPDIR/epa"; jun2026_assets "$a"
  d="$BATS_TEST_TMPDIR/epd"; mkdir -p "$d"; jun2026_ephemeral_invoice "$d/i.csv"
  db="$BATS_TEST_TMPDIR/ep.db"; build_db "$db" "$a" "$d" >/dev/null
  [ "$(sqlite3 "$db" "SELECT price_group FROM detected_group;")" = "eu" ]
  [ "$(sqlite3 "$db" "SELECT printf('%.2f', optimal) FROM priced;")" = "4.57" ]
}

@test "gelkao invoice audit -d <dir> runs the whole pipeline: extract, fetch (skip), audit" {
  d="$BATS_TEST_TMPDIR/g"; mkdir -p "$d"
  uuid=11111111-2222-3333-4444-555555555555
  invoice_csv "$d/K0000000000-2025-11-$uuid.csv"   # pre-seeded -> fetch skips, no network
  html="$BATS_TEST_TMPDIR/page.html"
  printf '<td>K0000000000</td><a href="https://usage.hetzner.com/%s">x</a>\n' "$uuid" > "$html"

  run bash -c "cat '$html' | '$ROOT/gelkao' invoice audit -d '$d' -"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]                     # fetch skipped the pre-seeded invoice in <dir> (no curl)
  [[ "$output" == *"would save"* ]]               # audit ran end-to-end
  [ -f "$d/gelkao.db" ]
}

@test "gelkao invoice audit ignores stdin unless given -" {
  d="$BATS_TEST_TMPDIR/ig"; mkdir -p "$d"
  invoice_csv "$d/K0000000000-2025-11-x.csv"
  run bash -c "echo 'not an invoice page' | '$ROOT/gelkao' invoice audit -q -d '$d'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would save"* ]]
}

@test "gelkao invoice audit -q is accepted and produces an audit" {
  d="$BATS_TEST_TMPDIR/q"; mkdir -p "$d"
  invoice_csv "$d/K0000000000-2025-11-x.csv"
  run bash -c "'$ROOT/gelkao' invoice audit -q -d '$d'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would save"* ]]
}

@test "require_sqlite rejects sqlite too old for common table expressions" {
  stub="$BATS_TEST_TMPDIR/old"; mkdir -p "$stub"
  printf '#!/bin/sh\necho "3.7.17 2013-05-20 00:48:51"\n' > "$stub/sqlite3"
  chmod +x "$stub/sqlite3"
  PATH="$stub:$PATH" run require_sqlite
  [ "$status" -ne 0 ]
  [[ "$output" == *"too old"* ]]
}

@test "require_sqlite accepts a modern sqlite" {
  stub="$BATS_TEST_TMPDIR/new"; mkdir -p "$stub"
  printf '#!/bin/sh\necho "3.40.1 2022-12-28 14:03:47"\n' > "$stub/sqlite3"
  chmod +x "$stub/sqlite3"
  PATH="$stub:$PATH" run require_sqlite
  [ "$status" -eq 0 ]
}

@test "require_sqlite accepts the sqlite a stable distro ships, below the old 3.32 floor" {
  stub="$BATS_TEST_TMPDIR/distro"; mkdir -p "$stub"
  printf '#!/bin/sh\necho "3.27.2 2019-02-25 16:06:06"\n' > "$stub/sqlite3"
  chmod +x "$stub/sqlite3"
  PATH="$stub:$PATH" run require_sqlite
  [ "$status" -eq 0 ]
}

@test "require_sqlite compares the patch level, not just major and minor" {
  stub="$BATS_TEST_TMPDIR/patch"; mkdir -p "$stub"
  printf '#!/bin/sh\necho "3.8.2 2013-12-06 14:53:30"\n' > "$stub/sqlite3"
  chmod +x "$stub/sqlite3"
  PATH="$stub:$PATH" run require_sqlite
  [ "$status" -ne 0 ]
}

@test "require_sqlite fails when sqlite3 is not installed" {
  PATH="$BATS_TEST_TMPDIR" run require_sqlite
  [ "$status" -ne 0 ]
  [[ "$output" == *"install sqlite3"* ]]
}

@test "require_curl fails when curl is not installed" {
  PATH="$BATS_TEST_TMPDIR" run require_curl
  [ "$status" -ne 0 ]
  [[ "$output" == *"install curl"* ]]
}

@test "resolve_asset prefers a live/ copy over the committed providers/ file, else falls back" {
  repo="$BATS_TEST_TMPDIR/repo"; mkdir -p "$repo/providers/hetzner" "$repo/live/hetzner"
  : > "$repo/providers/hetzner/prices.csv"
  : > "$repo/providers/hetzner/server_types.csv"

  run resolve_asset hetzner/server_types.csv "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = "$repo/providers/hetzner/server_types.csv" ]

  : > "$repo/live/hetzner/prices.csv"
  run resolve_asset hetzner/prices.csv "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = "$repo/live/hetzner/prices.csv" ]
}

@test "update_prices fails and leaves no override when the server has no file" {
  repo="$BATS_TEST_TMPDIR/repoF"; mkdir -p "$repo/providers/hetzner"
  : > "$repo/providers/hetzner/prices.csv"; : > "$repo/providers/hetzner/server_types.csv"

  curl() { return 22; }

  run update_prices https://gelkao.com "$repo/live"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to fetch"* ]]
  [ ! -f "$repo/live/hetzner/prices.csv" ]

  run resolve_asset hetzner/prices.csv "$repo"
  [ "$output" = "$repo/providers/hetzner/prices.csv" ]
}

@test "update_prices downloads both tables into live/hetzner and resolve_asset then prefers them" {
  repo="$BATS_TEST_TMPDIR/repoS"; mkdir -p "$repo/providers/hetzner"
  : > "$repo/providers/hetzner/prices.csv"; : > "$repo/providers/hetzner/server_types.csv"

  curl() {
    local f=""
    while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { f="$2"; shift; }; shift; done
    printf 'fresh\n' > "$f"
    return 0
  }

  run update_prices https://gelkao.com "$repo/live"
  [ "$status" -eq 0 ]
  [ -s "$repo/live/hetzner/prices.csv" ]
  [ -s "$repo/live/hetzner/server_types.csv" ]

  run resolve_asset hetzner/prices.csv "$repo"
  [ "$output" = "$repo/live/hetzner/prices.csv" ]
}

@test "maybe_refresh_prices is a no-op (no prompt, no fetch) when not interactive" {
  update_prices() { touch "$BATS_TEST_TMPDIR/fetched"; }

  run maybe_refresh_prices https://gelkao.com "$BATS_TEST_TMPDIR/live"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/fetched" ]
}
