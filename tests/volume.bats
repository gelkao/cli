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

@test "placement_rects lays each leaf's pools out inside it" {
  run placement_rects 100 100 <<'ROWS'
leaf-a	73	1
leaf-a	73	2
leaf-a	74	3
ROWS
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "${lines[0]}" = $'leaf\tleaf-a\t\t3\t'* ]]
  [[ "${lines[1]}" = $'pool\tleaf-a\t73\t2\t'* ]]
  [[ "${lines[2]}" = $'pool\tleaf-a\t74\t1\t'* ]]
  local ratio escaped
  ratio=$(printf '%s\n' "${lines[@]}" | awk -F'\t' '$1 == "pool" { area[$3] = $7 * $8 } END { printf "%.2f", area[73] / area[74] }')
  [ "$ratio" = "2.00" ]
  escaped=$(printf '%s\n' "${lines[@]}" | awk -F'\t' '
    $1 == "leaf" { lx = $5; ly = $6; lw = $7; lh = $8 }
    $1 == "pool" && ($5 < lx - 0.01 || $6 < ly - 0.01 || $5 + $7 > lx + lw + 0.01 || $6 + $8 > ly + lh + 0.01) { bad++ }
    END { print bad + 0 }')
  [ "$escaped" -eq 0 ]
}

@test "placement_rects insets each leaf so blank pixels separate the domains" {
  run placement_rects 100 100 <<'ROWS'
leaf-a	73	1
ROWS
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = $'leaf\tleaf-a\t\t1\t5.00\t5.00\t90.00\t90.00' ]
}

@test "placement_rects fills each leaf with its pools, edge to edge" {
  run placement_rects 100 100 <<'ROWS'
leaf-a	73	1
ROWS
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = $'pool\tleaf-a\t73\t1\t5.00\t5.00\t90.00\t90.00' ]
}

@test "colour_rects grades each leaf red, amber or green by how many volumes it carries" {
  run colour_rects <<RECTS
leaf	hot		20	0	0	10	10
leaf	warm		2	0	0	10	10
leaf	cool		1	0	0	10	10
RECTS
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" = *$'	#b22222	'* ]]
  [[ "${lines[1]}" = *$'	#c77c0c	'* ]]
  [[ "${lines[2]}" = *$'	#227a3f	'* ]]
}

@test "colour_rects bands each pool on the same rule as its leaf" {
  run colour_rects <<RECTS
leaf	hot		24	0	0	10	10
pool	hot	73	20	0	0	5	10
pool	hot	74	10	0	0	5	10
pool	hot	75	1	0	0	5	10
RECTS
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" = *$'	#b22222	'* ]]
  [[ "${lines[2]}" = *$'	#cc6f6f	'* ]]
  [[ "${lines[3]}" = *$'	#f3dddd	'* ]]
}

@test "colour_rects draws a green block solid, since its pools can never differ" {
  run colour_rects <<RECTS
leaf	cool		1	0	0	10	10
pool	cool	73	1	0	0	10	10
RECTS
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" = *$'	#227a3f	'* ]]
}

@test "rects_to_svg labels each leaf block with its name" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-leaf9		24	0	0	400	400	#b22222
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *">fsn1-leaf9<"* ]]
}

@test "rects_to_svg shortens the leaf name to region letter, cloud and leaf number" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-cloud2-leaf39		24	0	0	400	400	#b22222
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *">f-2-39<"* ]]
}

@test "rects_to_svg labels each volume group with its id" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-cloud2-leaf39		24	0	0	400	400	#b22222
pool	fsn1-cloud2-leaf39	173	15	0	0	400	200	#b22222
pool	fsn1-cloud2-leaf39	170	9	0	200	400	200	#cc6f6f
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *">#173<"* ]]
  [[ "$output" = *">#170<"* ]]
}

@test "colour_rects names an ink that stays legible on each fill" {
  run colour_rects <<RECTS
leaf	hot		24	0	0	10	10
pool	hot	73	20	0	0	5	10
pool	hot	74	1	0	0	5	10
RECTS
  [ "$status" -eq 0 ]
  [[ "${lines[1]}" = *$'	#b22222	#ffffff' ]]
  [[ "${lines[2]}" = *$'	#f3dddd	#3a3a3a' ]]
}

@test "rects_to_svg inks the leaf label to suit the pool beneath it" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-cloud2-leaf39		1	0	0	400	400	#c77c0c	#ffffff
pool	fsn1-cloud2-leaf39	45	1	0	0	400	400	#f6ebda	#3a3a3a
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *'fill="#3a3a3a">f-2-39<'* ]]
}

@test "rects_to_svg turns a volume group id sideways when its tile is tall and narrow" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-cloud2-leaf41		15	0	0	400	400	#c77c0c	#ffffff
pool	fsn1-cloud2-leaf41	37	1	0	0	23	209	#f6ebda	#3a3a3a
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *"rotate(-90"*">#37<"* ]]
}

@test "rects_to_svg inks a volume group id with the colour named for its fill" {
  run rects_to_svg 400 400 <<RECTS
leaf	fsn1-cloud2-leaf41		2	0	0	400	400	#227a3f	#ffffff
pool	fsn1-cloud2-leaf41	219	2	0	0	400	400	#227a3f	#ffffff
RECTS
  [ "$status" -eq 0 ]
  [[ "$output" = *'font-size="10" fill="#ffffff"'* ]]
}
