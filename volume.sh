#!/usr/bin/env bash

placement_rows_ranked() {
  local assets=$1
  require_sqlite
  sqlite3 :memory: \
    "CREATE TABLE attachment(id TEXT, pool TEXT, leaf TEXT);" \
    ".separator \"\t\"" \
    ".import '/dev/stdin' attachment" \
    ".read '$assets/placement.sql'"
}

placement_tree() {
  local id pool leaf shown_leaf='' shown_pool=''
  while IFS=$'\t' read -r leaf pool id; do
    if [[ "$leaf" != "$shown_leaf" ]]; then
      printf '%s\n' "$leaf"
      shown_leaf=$leaf; shown_pool=''
    fi
    if [[ "$pool" != "$shown_pool" ]]; then
      printf '    volume pool %s\n' "$pool"
      shown_pool=$pool
    fi
    printf '        %s\n' "$id"
  done
}

volume_show() {
  local assets=$1 rows
  rows=$(placement_rows_ranked "$assets")
  [[ -n "$rows" ]] || die "no placement rows on stdin - pipe in the table Hetzner support sent you"
  printf '%s\n' "$rows" | placement_tree
}

CANVAS_W=1280
CANVAS_H=800
CANVAS_BG='#fafaf9'
LEAF_FILL='#3f5c70'

leaf_sizes() {
  awk -F'\t' '
    !($1 in count) { order[++ranked] = $1 }
    { count[$1]++ }
    END { for (i = 1; i <= ranked; i++) printf "%s\t%d\n", order[i], count[order[i]] }
  '
}

squarified_rects() {
  local width=$1 height=$2
  awk -F'\t' -v W="$width" -v H="$height" '
    function worst(sum, biggest, smallest, side, scale,   area, wide, tall) {
      area = sum * scale
      if (area <= 0 || side <= 0 || smallest <= 0) return 1e18
      wide = side * side * biggest * scale / (area * area)
      tall = area * area / (side * side * smallest * scale)
      return (wide > tall ? wide : tall)
    }
    function emit(name, size, x, y, w, h) {
      printf "%s\t%d\t%.2f\t%.2f\t%.2f\t%.2f\n", name, size, x, y, w, h
    }
    { leaf[++n] = $1; size[n] = $2; total += $2 }
    END {
      if (n == 0 || total == 0) exit
      x = 0; y = 0; w = W; h = H
      scale = W * H / total
      first = 1
      while (first <= n) {
        side = (w < h ? w : h)
        sum = 0; biggest = 0; smallest = 0; taken = 0
        past = first
        while (past <= n) {
          v = size[past]
          try_biggest  = (taken == 0 || v > biggest  ? v : biggest)
          try_smallest = (taken == 0 || v < smallest ? v : smallest)
          if (taken > 0 && worst(sum + v, try_biggest, try_smallest, side, scale) > worst(sum, biggest, smallest, side, scale)) break
          sum += v; biggest = try_biggest; smallest = try_smallest; taken++
          past++
        }
        band = sum * scale
        if (w <= h) {
          depth = band / w
          offset = x
          for (k = first; k < past; k++) {
            span = size[k] * scale / depth
            emit(leaf[k], size[k], offset, y, span, depth)
            offset += span
          }
          y += depth; h -= depth
        } else {
          depth = band / h
          offset = y
          for (k = first; k < past; k++) {
            span = size[k] * scale / depth
            emit(leaf[k], size[k], x, offset, depth, span)
            offset += span
          }
          x += depth; w -= depth
        }
        first = past
      }
    }
  '
}

rects_to_svg() {
  local width=$1 height=$2
  awk -F'\t' -v W="$width" -v H="$height" -v bg="$CANVAS_BG" -v fill="$LEAF_FILL" '
    BEGIN {
      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">", W, H
      printf "<rect width=\"%d\" height=\"%d\" fill=\"%s\"/>", W, H, bg
    }
    { printf "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\"/>", $3, $4, $5, $6, fill, bg }
    END { print "</svg>" }
  '
}

svg_to_webp() {
  local out=$1
  mkdir -p "$(dirname "$out")"
  rsvg-convert | cwebp -quiet -o "$out" -- -
}

volume_draw() {
  local assets=$1 out=$2 rows
  require_rsvg
  require_cwebp
  rows=$(placement_rows_ranked "$assets")
  [[ -n "$rows" ]] || die "no placement rows on stdin - pipe in the table Hetzner support sent you"
  printf '%s\n' "$rows" \
    | leaf_sizes \
    | squarified_rects "$CANVAS_W" "$CANVAS_H" \
    | rects_to_svg "$CANVAS_W" "$CANVAS_H" \
    | svg_to_webp "$out"
  info 2 "wrote $out"
}
