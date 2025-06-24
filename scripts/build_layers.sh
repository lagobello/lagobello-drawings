#!/usr/bin/env bash
# build_layers.sh  –  DXF ➜ GPKG ➜ GeoJSON export
#
# Default:  *no* gzip (plain .geojson for GitHub Pages & OL)
# Optional: pass --gzip to also write .gz files
#
# usage: ./scripts/build_layers.sh path/to/file.dxf [--gzip]

set -euo pipefail

# -------- parse args ---------------------------------------------------------
GZIP_OUTPUT=0
[[ "${2-}" == "--gzip" ]] && GZIP_OUTPUT=1

SRC_DXF=${1:? "Usage: $0 path/to/source.dxf [--gzip]"}
GPKG="lagobello.gpkg"
WEBDIR="web"
SRS_IN="EPSG:2279"     # South Texas State Plane
SRS_OUT="EPSG:3857"    # Web Mercator

# Update this list whenever you add a new hatch layer in CAD
HATCH_LAYERS=(
  PLAT-HATCH-CAMINATA
  PLAT-HATCH-CAMINATA-PROPOSED
  PLAT-HATCH-FOUNTAIN
  PLAT-HATCH-LOTS
  PLAT-HATCH-STREET
  PLAT-HATCH-STREET-ACCESS
  PLAT-HATCH-STREET-RESERVE
)

# -------- rebuild GPKG -------------------------------------------------------
echo ">> Re-creating $GPKG from $(basename "$SRC_DXF")"
rm -f "$GPKG"
ogr2ogr -f GPKG "$GPKG" "$SRC_DXF" \
        -a_srs "$SRS_IN" -nlt PROMOTE_TO_MULTI \
        -lco GEOMETRY_NAME=geom

mkdir -p "$WEBDIR"

# -------- export one GeoJSON per HATCH layer ---------------------------------
echo ">> Exporting hatch layers"
for LAYER in "${HATCH_LAYERS[@]}"; do
  OUT="$WEBDIR/${LAYER}.geojson"
  echo "   • $LAYER → $(basename "$OUT")"
  ogr2ogr -f GeoJSON "$OUT" "$GPKG" entities \
          -dialect SQLite -where "Layer='${LAYER}'" \
          -t_srs "$SRS_OUT" -nln "$LAYER"
  [[ $GZIP_OUTPUT -eq 1 ]] && gzip -9 -f "$OUT"
done

# -------- export *all other* layers into one GeoJSON -------------------------
NON="$WEBDIR/non_hatch_layers.geojson"
echo ">> Exporting NON-hatch layers → $(basename "$NON")"
ogr2ogr -f GeoJSON "$NON" "$GPKG" entities \
        -dialect SQLite -where "Layer NOT LIKE 'PLAT-HATCH%'" \
        -t_srs "$SRS_OUT" -nln non_hatch_layers
[[ $GZIP_OUTPUT -eq 1 ]] && gzip -9 -f "$NON"

echo "✓ Build complete.  Files are in $WEBDIR/."
[[ $GZIP_OUTPUT -eq 0 ]] && echo "  (gzip skipped — pass --gzip to create .gz copies)"
