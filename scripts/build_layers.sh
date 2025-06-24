#!/usr/bin/env bash
# build_layers.sh   DXF ▶ GPKG ▶ GeoJSONs  (layer attr filtering)
# -----------------------------------------------------------------
# usage: ./scripts/build_layers.sh path/to/source.dxf
set -euo pipefail

SRC_DXF=${1:? "Usage: $0 path/to/source.dxf"}
GPKG="lagobello.gpkg"
WEBDIR="web"
SRS_IN="EPSG:2279"     # South Texas State Plane
SRS_OUT="EPSG:3857"    # Web Mercator for OL

# List your hatch layers here
HATCH_LAYERS=(
  PLAT-HATCH-CAMINATA
  PLAT-HATCH-CAMINATA-PROPOSED
  PLAT-HATCH-FOUNTAIN
  PLAT-HATCH-LOTS
  PLAT-HATCH-STREET
  PLAT-HATCH-STREET-ACCESS
  PLAT-HATCH-STREET-RESERVE
)

echo ">> Re-creating $GPKG ..."
rm -f "$GPKG"
ogr2ogr -f GPKG "$GPKG" "$SRC_DXF" -a_srs "$SRS_IN" \
        -nlt PROMOTE_TO_MULTI -lco GEOMETRY_NAME=geom

mkdir -p "$WEBDIR"

# ---------- one GeoJSON per HATCH layer --------------------------
echo ">> Exporting hatch layers"
for LAYER in "${HATCH_LAYERS[@]}"; do
  OUT="$WEBDIR/${LAYER}.geojson"
  echo "   • $LAYER  →  $(basename "$OUT").gz"
  ogr2ogr -f GeoJSON "$OUT" "$GPKG" entities \
          -t_srs "$SRS_OUT" \
          -dialect SQLite \
          -where "Layer='${LAYER}'" \
          -nln "$LAYER"
  gzip -9 -f "$OUT"
done

# ---------- ONE GeoJSON for all NON-HATCH layers -----------------
echo ">> Exporting non-hatch layers into one file"
NON="$WEBDIR/non_hatch_layers.geojson"
ogr2ogr -f GeoJSON "$NON" "$GPKG" entities \
        -t_srs "$SRS_OUT" \
        -dialect SQLite \
        -where "Layer NOT LIKE 'PLAT-HATCH%'" \
        -nln non_hatch_layers
gzip -9 -f "$NON"

echo "✓ Done.  GeoJSONs are in $WEBDIR/ (gzipped)."
