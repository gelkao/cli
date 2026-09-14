#!/usr/bin/env bash

UUID_RE='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
CN_RE='K[0-9]{10}'
SQLITE_FLOOR='3.8.3'

die() { echo "error: $*" >&2; exit 1; }

version_number() {
  local major minor patch
  IFS=. read -r major minor patch <<<"$1"
  printf '%d%03d%03d' "$major" "${minor:-0}" "${patch:-0}"
}

require_sqlite() {
  command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found - install sqlite3 (3.8.3+ required)"
  local ver
  ver=$(sqlite3 --version | cut -d' ' -f1)
  if [[ "$(version_number "$ver")" -lt "$(version_number "$SQLITE_FLOOR")" ]]; then
    die "sqlite3 $ver is too old - need $SQLITE_FLOOR+ for common table expressions"
  fi
}

require_curl() {
  command -v curl >/dev/null 2>&1 || die "curl not found - install curl to download invoices"
}

require_rsvg() {
  command -v rsvg-convert >/dev/null 2>&1 || die "rsvg-convert not found - install librsvg to draw the placement map"
}

require_cwebp() {
  command -v cwebp >/dev/null 2>&1 || die "cwebp not found - install libwebp to draw the placement map"
}

info() {
  local fd=$1 msg=$2 g='' r=''
  [ -t "$fd" ] && { g=$'\e[90m'; r=$'\e[0m'; }
  if [ "$fd" = 2 ]; then printf '%s%s%s\n' "$g" "$msg" "$r" >&2
  else printf '%s%s%s\n' "$g" "$msg" "$r"; fi
}

# shellcheck disable=SC2120
extract_uuids() {
  grep -ohiE "usage\.hetzner\.com/${UUID_RE}" "$@" | sed 's|.*/||'
}

# shellcheck disable=SC2120
extract_cn() {
  local found n
  found=$(grep -ohE 'K[0-9]+' "$@" | grep -xE "$CN_RE" | sort -u || true)
  n=$(printf '%s' "$found" | grep -c . || true)
  case "$n" in
    1) printf '%s\n' "$found" ;;
    0) die "no customer number in the invoice page - expected a K followed by digits" ;;
    *) die "several customer numbers in the input ($(printf '%s' "$found" | tr '\n' ' ')) - audit one account at a time" ;;
  esac
}

is_customer_number() { [[ "$1" =~ ^${CN_RE}$ ]]; }

list_invoices() {
  local page cn uuids
  page=$(cat "$@")
  cn=$(printf '%s' "$page" | extract_cn) || exit 1
  uuids=$(printf '%s' "$page" | extract_uuids || true)
  if [[ -z "$uuids" ]]; then
    echo "warning: no UUIDs found - has Hetzner changed the invoice URL?" >&2
    return 1
  fi
  printf '%s\n%s\n' "$cn" "$uuids"
}

invoice_csv_url() { printf 'https://usage.hetzner.com/%s?csv&cn=%s' "$1" "$2"; }

month_of_csv() {
  local d
  d=$(grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" | head -1 || true)
  if [ -n "$d" ]; then
    printf '%s' "${d:0:7}"
    return
  fi
  d=$(grep -oE '[0-9]{2}\.[0-9]{2}\.[0-9]{4}' "$1" | head -1 || true)
  [ -n "$d" ] && printf '%s-%s' "${d:6:4}" "${d:3:2}"
}


fetch_one() {
  local uuid=$1 cn=$2 data_dir=$3 staging month out
  local existing=( "$data_dir/${cn}"-*-"${uuid}.csv" )

  if [[ -e "${existing[0]}" ]]; then
    info 1 "skip"$'\t'"${existing[0]}"
    return 10
  fi

  require_curl
  staging="$data_dir/.${uuid}.part"
  if ! curl -sSfL -o "$staging" "$(invoice_csv_url "$uuid" "$cn")"; then
    rm -f "$staging"
    printf 'fail\t%s\n' "$uuid" >&2
    return 1
  fi

  month=$(month_of_csv "$staging")
  if [[ -z "$month" ]]; then
    rm -f "$staging"
    printf 'fail\t%s\tno-dates\n' "$uuid" >&2
    return 1
  fi

  out="$data_dir/${cn}-${month}-${uuid}.csv"
  mv "$staging" "$out"
  info 1 "ok"$'\t'"$out"
  return 0
}

customer_number_in_stream() {
  local line cn=''
  while read -r line; do
    is_customer_number "$line" || continue
    [[ -z "$cn" || "$cn" = "$line" ]] || die "several customer numbers on stdin ($cn and $line) - fetch one account at a time"
    cn=$line
  done
  [[ -n "$cn" ]] || die "no customer number on stdin - pipe the output of 'gelkao list' in"
  printf '%s\n' "$cn"
}

uuids_in_stream() { grep -vE "^${CN_RE}$" || true; }

download_each() {
  local cn=$1 data_dir=$2 uuid rc ok=0 skip=0 fail=0
  while read -r uuid; do
    [[ -n "${uuid:-}" ]] || continue
    rc=0
    fetch_one "$uuid" "$cn" "$data_dir" || rc=$?
    case $rc in
      0)  ok=$((ok+1)) ;;
      10) skip=$((skip+1)) ;;
      *)  fail=$((fail+1)) ;;
    esac
  done
  info 2 "Done. downloaded=$ok skipped=$skip failed=$fail"
}

fetch_all() {
  local data_dir=${1:-data} stream cn
  stream=$(cat)
  cn=$(printf '%s\n' "$stream" | customer_number_in_stream) || exit 1
  mkdir -p "$data_dir"
  printf '%s\n' "$stream" | uuids_in_stream | download_each "$cn" "$data_dir"
}

import_csv_without_header() {
  local db=$1 file=$2 table=$3
  sqlite3 "$db" \
    "DROP TABLE IF EXISTS staging_csv;
     CREATE TABLE staging_csv AS SELECT * FROM $table WHERE 0;" \
    ".mode csv" \
    ".import '$file' staging_csv" \
    "DELETE FROM staging_csv WHERE rowid = (SELECT MIN(rowid) FROM staging_csv);
     INSERT INTO $table SELECT * FROM staging_csv;
     DROP TABLE staging_csv;"
}

import_invoices() {
  local db=$1 data_dir=$2 f found=0
  for f in "$data_dir"/*.csv; do
    [ -e "$f" ] || continue
    import_csv_without_header "$db" "$f" raw_invoices 2>/dev/null
    found=1
  done
  [ "$found" = 1 ] || die "no invoice CSVs in $data_dir/"
}

resolve_asset() {
  local rel=$1 repo=$2 live
  live="${LIVE_DIR:-$repo/live}"
  if [ -f "$live/$rel" ]; then printf '%s' "$live/$rel"; else printf '%s' "$repo/providers/$rel"; fi
}

update_prices() {
  local base=$1 live=$2 rel rc=0
  for rel in hetzner/prices.csv hetzner/server_types.csv; do
    mkdir -p "$(dirname "$live/$rel")"
    if curl -sSfL -o "$live/$rel" "$base/$rel"; then
      echo "updated $live/$rel" >&2
    else
      rm -f "$live/$rel"
      echo "failed to fetch $base/$rel" >&2
      rc=1
    fi
  done
  return $rc
}

maybe_refresh_prices() {
  local base=$1 live=$2 quiet=${3:-0} ans
  if [ "$quiet" = 1 ] || [ ! -t 1 ]; then return 0; fi
  printf 'Hetzner changes its prices every few months - fetch the latest from %s? [Y/n] ' "$base" > /dev/tty
  read -r ans < /dev/tty || return 0
  case "$ans" in [Nn]*) return 0 ;; esac
  update_prices "$base" "$live" || echo "price refresh failed; keeping committed prices" >&2
}

build_db() {
  local db=$1 assets=$2 data_dir=$3 prices spec
  require_sqlite
  prices=$(resolve_asset hetzner/prices.csv "$assets")
  spec=$(resolve_asset hetzner/server_types.csv "$assets")
  [ -f "$prices" ] || die "missing prices.csv (resolved to $prices)"
  [ -f "$spec" ]   || die "missing server_types.csv (resolved to $spec)"
  rm -f "$db"
  sqlite3 "$db" < "$assets/schema.sql"
  import_invoices "$db" "$data_dir"
  import_csv_without_header "$db" "$prices" prices
  import_csv_without_header "$db" "$spec" server_types
  sqlite3 "$db" < "$assets/normalize.sql"
  sqlite3 "$db" < "$assets/audit.sql"
}

grouping_filter() {
  [ -n "${1:-}" ] || return 0
  printf "WHERE grouping = '%s'" "${1//\'/\'\'}"
}

stat_period()         { sqlite3 "$1" "SELECT printf('%s .. %s  (%d months)', MIN(month), MAX(month), COUNT(DISTINCT month)) FROM priced ${2:-};"; }
stat_currency()       { sqlite3 "$1" "SELECT upper(MIN(currency)) FROM priced ${2:-};"; }
stat_servers()        { sqlite3 "$1" "SELECT COUNT(DISTINCT box) FROM priced ${2:-};"; }
account_price_group() { sqlite3 "$1" "SELECT COALESCE((SELECT price_group FROM detected_group), 'unknown');"; }
stat_total_paid()     { sqlite3 "$1" "SELECT printf('%.2f', SUM(paid)) FROM priced ${2:-};"; }
stat_run_rate()       { sqlite3 "$1" "SELECT printf('%.2f', SUM(CASE WHEN month = (SELECT MAX(month) FROM priced ${2:-}) THEN paid ELSE 0 END)) FROM priced ${2:-};"; }
stat_savings_pct()    { sqlite3 "$1" "SELECT printf('%.1f', (SUM(paid) - SUM(optimal)) * 100.0 / SUM(paid)) FROM priced ${2:-};"; }
stat_savings_amount() { sqlite3 "$1" "SELECT printf('%.0f', round(SUM(paid) - SUM(optimal))) FROM priced ${2:-};"; }

savings_color() {
  if   [ "$1" -ge 50 ]; then printf '%s' "$2"
  elif [ "$1" -ge 20 ]; then printf '%s' "$3"
  else                       printf '%s' "$4"; fi
}

report() {
  local db=$1 grouping=${2:-} filter rule='------------------------------------------------------------------'
  local b='' r='' red='' amber='' green='' prefix bar pct c spct spi
  if [ -t 1 ]; then
    b=$'\e[1m'; r=$'\e[0m'
    red=$'\e[1;31m'; amber=$'\e[1;33m'; green=$'\e[1;32m'
  fi
  filter=$(grouping_filter "$grouping")

  printf 'period            : %s%s%s\n'                       "$b" "$(stat_period      "$db" "$filter")" "$r"
  printf 'currency          : %s%s%s\n' "$b" "$(stat_currency "$db" "$filter")" "$r"
  printf 'servers analysed  : %s%s%s\n'                       "$b" "$(stat_servers     "$db" "$filter")" "$r"
  printf 'price group       : %s%s%s\n'                       "$b" "$(account_price_group "$db")" "$r"
  printf 'total paid        : %s€%s%s\n'                      "$b" "$(stat_total_paid  "$db" "$filter")" "$r"
  printf 'current run-rate  : %s€%s%s/mo\n'    "$b" "$(stat_run_rate    "$db" "$filter")" "$r"
  printf '%s\n' "$rule"
  spct=$(stat_savings_pct "$db" "$filter")
  printf -v spi '%.0f' "$spct"
  printf 'cheapest same-spec each month would save : %s%s%%%s  (%s€%s%s)\n' \
         "$(savings_color "$spi" "$red" "$amber" "$green")" "$spct" "$r" \
         "$b" "$(stat_savings_amount "$db" "$filter")" "$r"
  printf '%s\n' "$rule"

  while IFS='|' read -r prefix bar pct; do
    c=$(savings_color "$pct" "$red" "$amber" "$green")
    printf '%s%s%s %s%%%s\n' "$prefix" "$c" "$bar" "$pct" "$r"
  done < <(sqlite3 "$db" <<SQL
SELECT printf('%s  paid %-6.0f optimal %-6.0f |%s|%.0f',
              month, round(SUM(paid)), round(SUM(optimal)),
              substr('########################################', 1,
                     CASE WHEN SUM(paid) > 0
                          THEN MAX(0, CAST((SUM(paid) - SUM(optimal)) * 40.0 / SUM(paid) AS INT))
                          ELSE 0 END),
              round(CASE WHEN SUM(paid) > 0
                   THEN (SUM(paid) - SUM(optimal)) * 100.0 / SUM(paid) ELSE 0 END))
FROM priced $filter
GROUP BY month
ORDER BY month;
SQL
)
}

audit() {
  local assets=$1 data_dir=$2 db="${3:-$2/gelkao.db}" grouping=${4:-} quiet=${5:-0}
  maybe_refresh_prices "${GELKAO_PRICES_URL:-https://gelkao.com/live}" "${LIVE_DIR:-$assets/live}" "$quiet"
  build_db "$db" "$assets" "$data_dir"
  report "$db" "$grouping"
}

run_pipeline() {
  local assets=$1 data_dir=${2:-data} db=${3:-} grouping=${4:-} quiet=${5:-0} page cn uuids
  page=$(cat)
  cn=$(printf '%s' "$page" | extract_cn) || exit 1
  uuids=$(printf '%s' "$page" | extract_uuids || true)
  [[ -n "$uuids" ]] || die "no invoice UUIDs found on stdin"
  printf '%s\n%s\n' "$cn" "$uuids" | fetch_all "$data_dir" >&2
  audit "$assets" "$data_dir" "$db" "$grouping" "$quiet"
}
