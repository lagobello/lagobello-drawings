#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_layers.sh – DXF ➜ GeoPackage ➜ GeoJSON exporter for Lago Bello
#
# • Creates   <input>.gpkg   (EPSG:2279 – Texas South ft)
# • Writes    <layer>.geojson for every DXF layer that contains HATCH
#   elements (detected via SubClasses LIKE '%Hatch%').
#   – We run ogr2ogr first → if resulting file is empty, we delete it.
# • Writes    <basename>_non_hatch.geojson for everything else.
# • Optional  --gzip   adds .gz copies.
#
# usage: ./scripts/build_layers.sh path/to/file.dxf [--gzip]
# ---------------------------------------------------------------------------

set -euo pipefail

[[ $# -lt 1 ]] && { echo "Usage: $0 path/to/file.dxf [--gzip]"; exit 1; }

SRC_DXF=$1
GZIP_OUTPUT=0
[[ "${2-}" == "--gzip" ]] && GZIP_OUTPUT=1

# ---------- paths -----------------------------------------------------------
BASENAME="$(basename "$SRC_DXF" .dxf)"
DIRNAME="$(dirname  "$SRC_DXF")"
GPKG="${DIRNAME}/${BASENAME}.gpkg"
WEBDIR="web"

SRS_IN="EPSG:2279"   # Texas South ft
SRS_OUT="EPSG:3857"  # Web-Mercator

mkdir -p "$WEBDIR"

# ---------- build GeoPackage -----------------------------------------------
echo ">> Creating ${GPKG}"
rm -f "$GPKG"
ogr2ogr -f GPKG "$GPKG" "$SRC_DXF" \
        -a_srs "$SRS_IN" -nlt PROMOTE_TO_MULTI \
        -lco GEOMETRY_NAME=geom

# ---------- discover layers with HATCH elements ----------------------------
echo ">> Detecting HATCH layers …"
readarray -t HATCH_LAYERS < <(
  ogrinfo -ro -q "$GPKG" entities \
     -dialect SQLite \
     -sql "SELECT DISTINCT Layer FROM entities WHERE SubClasses LIKE '%Hatch%'" |
  awk -F'= ' '/Layer \(String\)/{
       gsub(/"/,"",$2);  gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2);
       print $2
  }' | sort
)

if [[ ${#HATCH_LAYERS[@]} -eq 0 ]]; then
  echo "   • No hatch layers found – nothing to export individually."
else
  echo "   • Found ${#HATCH_LAYERS[@]} hatch layers:"
  printf '     - %s\n' "${HATCH_LAYERS[@]}"
fi

# ---------- export each candidate layer, keep only if non-empty ------------
for LAYER in "${HATCH_LAYERS[@]}"; do
  TMP="$WEBDIR/${LAYER}.geojson.tmp"
  FINAL="$WEBDIR/${LAYER}.geojson"

  ogr2ogr -f GeoJSON "$TMP" "$GPKG" entities \
          -dialect SQLite \
          -where "Layer='${LAYER}' AND SubClasses LIKE '%Hatch%'" \
          -t_srs "$SRS_OUT" -nln "$LAYER" >/dev/null 2>&1

  if [[ -s "$TMP" ]]; then
    mv "$TMP" "$FINAL"
    echo "   • Exported ${LAYER} → $(basename "$FINAL") ($(wc -c < "$FINAL") B)"
    [[ $GZIP_OUTPUT -eq 1 ]] && gzip -9 -f "$FINAL"
  else
    rm -f "$TMP"
    echo "   • skipping ${LAYER} (0 features)"
  fi
done

# ---------- export NON-hatch layers (always) -------------------------------
NON="$WEBDIR/${BASENAME}_non_hatch.geojson"
echo ">> Exporting NON-hatch layers → $(basename "$NON")"
ogr2ogr -f GeoJSON "$NON" "$GPKG" entities \
        -dialect SQLite \
        -where "SubClasses NOT LIKE '%Hatch%'" \
        -t_srs "$SRS_OUT" -nln non_hatch_layers
[[ $GZIP_OUTPUT -eq 1 ]] && gzip -9 -f "$NON"

# ---------- done -----------------------------------------------------------
echo "✓ Done.  GeoPackage: $GPKG"
[[ $GZIP_OUTPUT -eq 0 ]] && echo "  (gzip skipped — pass --gzip to create .gz copies)"
