#!/usr/bin/env bash

placement_rows_ranked() {
  local assets=$1
  if [ -t 0 ]; then
    die "volume reads the placement table on stdin - pipe in the file Hetzner support sent you"
  fi
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
RAG_RED='178 34 34'
RAG_AMBER='199 124 12'
RAG_GREEN='34 122 63'
RED_VOLUMES=20
AMBER_VOLUMES=2
POOL_SHADE_AMBER=0.35
POOL_SHADE_GREEN=0.62
LEAF_GUTTER=10
LABEL_SIZE=13
LABEL_ADVANCE=0.50
LABEL_INK='#ffffff'

leaf_sizes() {
  awk -F'\t' '
    !($1 in count) { order[++ranked] = $1 }
    { count[$1]++ }
    END { for (i = 1; i <= ranked; i++) printf "%s\t%d\n", order[i], count[order[i]] }
  '
}

pool_sizes() {
  local leaf=$1
  awk -F'\t' -v leaf="$leaf" '
    $1 != leaf { next }
    !($2 in count) { order[++ranked] = $2 }
    { count[$2]++ }
    END { for (i = 1; i <= ranked; i++) printf "%s\t%d\n", order[i], count[order[i]] }
  '
}

squarified_rects() {
  local left=$1 top=$2 width=$3 height=$4
  awk -F'\t' -v X="$left" -v Y="$top" -v W="$width" -v H="$height" '
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
      x = X; y = Y; w = W; h = H
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

inset_rects() {
  local margin=$1
  awk -F'\t' -v m="$margin" '
    function shrunk(side) { return (side > m ? side - m : 0) }
    { printf "%s\t%s\t%.2f\t%.2f\t%.2f\t%.2f\n", $1, $2, $3 + m / 2, $4 + m / 2, shrunk($5), shrunk($6) }
  '
}

placement_rects() {
  local width=$1 height=$2 rows leaf leaf_size x y w h
  rows=$(cat)
  while IFS=$'\t' read -r leaf leaf_size x y w h; do
    printf 'leaf\t%s\t\t%s\t%s\t%s\t%s\t%s\n' "$leaf" "$leaf_size" "$x" "$y" "$w" "$h"
    printf '%s\n' "$rows" | pool_sizes "$leaf" | squarified_rects "$x" "$y" "$w" "$h" \
      | awk -F'\t' -v leaf="$leaf" '{ printf "pool\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n", leaf, $1, $2, $3, $4, $5, $6 }'
  done < <(printf '%s\n' "$rows" | leaf_sizes | squarified_rects 0 0 "$width" "$height" | inset_rects "$LEAF_GUTTER")
}

colour_rects() {
  awk -F'\t' -v red="$RAG_RED" -v amber="$RAG_AMBER" -v green="$RAG_GREEN" \
             -v red_at="$RED_VOLUMES" -v amber_at="$AMBER_VOLUMES" \
             -v shade_amber="$POOL_SHADE_AMBER" -v shade_green="$POOL_SHADE_GREEN" '
    function graded(volumes) {
      if (volumes >= red_at) return red
      if (volumes >= amber_at) return amber
      return green
    }
    function lightened(rgb, amount,   channel, i, hex) {
      split(rgb, channel, " ")
      hex = "#"
      for (i = 1; i <= 3; i++) hex = hex sprintf("%02x", int(channel[i] + (255 - channel[i]) * amount))
      return hex
    }
    function shade(leaf_volumes, pool_volumes) {
      if (leaf_volumes < amber_at) return 0
      if (pool_volumes >= red_at) return 0
      if (pool_volumes >= amber_at) return shade_amber
      return shade_green
    }
    { row[NR] = $0; level[NR] = $1; leaf[NR] = $2; size[NR] = $4 }
    END {
      for (i = 1; i <= NR; i++) {
        if (level[i] == "leaf") { base[leaf[i]] = graded(size[i]); leaf_volumes[leaf[i]] = size[i] }
        printf "%s\t%s\n", row[i], lightened(base[leaf[i]], level[i] == "leaf" ? 0 : shade(leaf_volumes[leaf[i]], size[i]))
      }
    }
  '
}

rects_to_svg() {
  local width=$1 height=$2
  awk -F'\t' -v W="$width" -v H="$height" -v bg="$CANVAS_BG" \
             -v size="$LABEL_SIZE" -v advance="$LABEL_ADVANCE" -v ink="$LABEL_INK" '
    function label_of(name, volumes) { return sprintf("%s (%d)", name, volumes) }
    function label_width(text) { return length(text) * size * advance }
    function fits(text, w, h) { return w >= label_width(text) + size && h >= size * 2 }
    function draw_label(text, x, y, colour,   pad) {
      pad = size / 2
      printf "<rect x=\"%s\" y=\"%s\" width=\"%.1f\" height=\"%.1f\" fill=\"%s\"/>", \
             x, y, label_width(text) + pad * 2, size * 1.5, colour
      printf "<text x=\"%.1f\" y=\"%.1f\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"%d\" font-weight=\"bold\" fill=\"%s\">%s</text>", \
             x + pad, y + size * 1.1, size, ink, text
    }
    BEGIN {
      printf "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\">", W, H
      printf "<rect width=\"%d\" height=\"%d\" fill=\"%s\"/>", W, H, bg
    }
    {
      printf "<rect x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" fill=\"%s\" stroke=\"%s\"/>", $5, $6, $7, $8, $9, bg
      if ($1 == "leaf") { labelled[++pending] = $0 }
    }
    END {
      for (i = 1; i <= pending; i++) {
        split(labelled[i], f, "\t")
        text = label_of(f[2], f[4])
        if (fits(text, f[7], f[8])) draw_label(text, f[5], f[6], f[9])
      }
      print "</svg>"
    }
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
    | placement_rects "$CANVAS_W" "$CANVAS_H" \
    | colour_rects \
    | rects_to_svg "$CANVAS_W" "$CANVAS_H" \
    | svg_to_webp "$out"
  info 2 "wrote $out"
}
