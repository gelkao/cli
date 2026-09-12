#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # shellcheck source=../lib.sh
  source "$ROOT/lib.sh"
  # shellcheck source=../volume.sh
  source "$ROOT/volume.sh"
}

@test "placement_rows_ranked drops the header and the CRLF the mail attachment carries" {
  run placement_rows_ranked "$ROOT" < <(printf 'volume id\tvolume pool id\tleaf\r\n900000001\t73\tfsn1-cloud9-leaf21\r\n')
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'fsn1-cloud9-leaf21\t73\t900000001' ]
}

@test "placement_rows_ranked ignores a line that is not a placement row" {
  run placement_rows_ranked "$ROOT" <<'ROWS'
Best regards	Jonas	Keidel
900000001	73	leaf-a
ROWS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = $'leaf-a\t73\t900000001' ]
}

@test "placement_rows_ranked puts the widest blast radius first - most volumes, not lowest name" {
  run placement_rows_ranked "$ROOT" <<'ROWS'
1	73	leaf-a
2	80	leaf-z
3	79	leaf-z
4	79	leaf-z
ROWS
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'leaf-z\t79\t3' ]
  [ "${lines[1]}" = $'leaf-z\t79\t4' ]
  [ "${lines[2]}" = $'leaf-z\t80\t2' ]
  [ "${lines[3]}" = $'leaf-a\t73\t1' ]
}

@test "placement_rows_ranked breaks ties by name and pool id, so the order never churns" {
  run placement_rows_ranked "$ROOT" <<'ROWS'
2	91	leaf-b
1	90	leaf-a
ROWS
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'leaf-a\t90\t1' ]
  [ "${lines[1]}" = $'leaf-b\t91\t2' ]
}

@test "placement_rows_ranked keeps pools apart when two leaves share a pool number" {
  run placement_rows_ranked "$ROOT" <<'ROWS'
1	5	leaf-a
2	5	leaf-b
ROWS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = $'leaf-a\t5\t1' ]
  [ "${lines[1]}" = $'leaf-b\t5\t2' ]
}

@test "placement_tree prints each leaf and pool once, then the volumes under them" {
  run placement_tree <<'ROWS'
leaf-a	73	1
leaf-a	73	2
leaf-a	74	3
leaf-b	80	4
ROWS
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "leaf-a" ]
  [ "${lines[1]}" = "    volume pool 73" ]
  [ "${lines[2]}" = "        1" ]
  [ "${lines[3]}" = "        2" ]
  [ "${lines[4]}" = "    volume pool 74" ]
  [ "${lines[5]}" = "        3" ]
  [ "${lines[6]}" = "leaf-b" ]
  [ "${lines[7]}" = "    volume pool 80" ]
  [ "${lines[8]}" = "        4" ]
  [ "${#lines[@]}" -eq 9 ]
}

@test "gelkao volume show turns the attachment on stdin into the tree" {
  run bash -c "printf 'volume id\tvolume pool id\tleaf\n900000001\t73\tleaf-a\n' | '$ROOT/gelkao' volume show"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "leaf-a" ]
  [ "${lines[1]}" = "    volume pool 73" ]
  [ "${lines[2]}" = "        900000001" ]
}

@test "gelkao volume show fails when stdin holds no placement rows" {
  run bash -c "printf 'volume id\tvolume pool id\tleaf\n' | '$ROOT/gelkao' volume show"
  [ "$status" -ne 0 ]
  [[ "$output" = *"no placement rows"* ]]
}

@test "gelkao volume rejects a subcommand it does not have" {
  run bash -c "printf '' | '$ROOT/gelkao' volume label"
  [ "$status" -ne 0 ]
  [[ "$output" = *"unknown volume subcommand"* ]]
}

@test "gelkao volume draw turns the placement on stdin into a webp" {
  command -v rsvg-convert >/dev/null && command -v cwebp >/dev/null \
    || skip "needs rsvg-convert and cwebp"
  local out="$BATS_TEST_TMPDIR/fleet.webp"
  run bash -c "printf 'volume id\tvolume pool id\tleaf\n900000001\t73\tleaf-a\n' | '$ROOT/gelkao' volume draw -o '$out'"
  [ "$status" -eq 0 ]
  [ -s "$out" ]
  run bash -c "head -c 12 '$out' | tr -d '\000'"
  [[ "$output" = RIFF*WEBP ]]
}

@test "gelkao volume draw says where it put the file" {
  command -v rsvg-convert >/dev/null && command -v cwebp >/dev/null \
    || skip "needs rsvg-convert and cwebp"
  local out="$BATS_TEST_TMPDIR/named.webp"
  run bash -c "printf 'volume id\tvolume pool id\tleaf\n900000001\t73\tleaf-a\n' | '$ROOT/gelkao' volume draw -o '$out' 2>&1"
  [ "$status" -eq 0 ]
  [[ "$output" = *"$out"* ]]
}
