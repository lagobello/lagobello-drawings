#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build_layers.sh – DXF ➜ GeoPackage ➜ GeoJSON + KML exporter
#
# • Creates <input>.gpkg   (EPSG:2279 – Texas South ft)
# • For every DXF layer that contains HATCH entities:
#       web/<layer>.geojson   (EPSG:3857)   [--gzip option]
#       web/<layer>.kml       (EPSG:4326)
# • Writes  web/<basename>_non_hatch.geojson  +  .kml  for everything else
# • GeoJSON names/paths unchanged, so no web-page edits needed.
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

SRS_IN="EPSG:2279"   # Texas South ft (input)
SRS_GJ="EPSG:3857"   # Web Mercator  (GeoJSON)
SRS_KML="EPSG:4326"  # WGS-84 (required by KML)

mkdir -p "$WEBDIR"

# ---------- build GeoPackage -----------------------------------------------
echo ">> Creating ${GPKG}"
rm -f "$GPKG"
ogr2ogr -f GPKG "$GPKG" "$SRC_DXF" \
        -a_srs "$SRS_IN" -nlt PROMOTE_TO_MULTI \
        -lco GEOMETRY_NAME=geom

# ---------- discover hatch layers ------------------------------------------
echo ">> Detecting HATCH layers …"
readarray -t HATCH_LAYERS < <(
  ogrinfo -ro -q "$GPKG" entities \
     -dialect SQLite \
     -sql "SELECT DISTINCT Layer FROM entities WHERE SubClasses LIKE '%Hatch%'" |
  awk -F'= ' '/Layer \(String\)/{
       gsub(/"/,"",$2); gsub(/^[[:space:]]+|[[:space:]]+$/,"",$2); print $2 }' |
  sort
)

MISNAMED_STREET="PLAT-HATCH-STREET-S3"
for i in "${!HATCH_LAYERS[@]}"; do
  if [[ ${HATCH_LAYERS[$i]} == "$MISNAMED_STREET" ]]; then
    echo "   • WARNING: detected misnamed layer '$MISNAMED_STREET'" >&2
    echo "     it will be exported as 'PLAT-HATCH-ROW-S3'" >&2
  fi
done

[[ ${#HATCH_LAYERS[@]} -eq 0 ]] && echo "   • No hatch layers found." \
                                 || printf "   • %s hatch layers: %s\n" \
                                   "${#HATCH_LAYERS[@]}" "${HATCH_LAYERS[*]}"

# ---------- export helper ---------------------------------------------------
export_layer () {        # $1=SQL where  $2=stem  (no ext)
  local WHERE="$1" STEM="$2"
  local GJ="$WEBDIR/${STEM}.geojson"
  local KML="$WEBDIR/${STEM}.kml"

  ogr2ogr -f GeoJSON "$GJ.tmp" "$GPKG" entities \
          -dialect SQLite -where "$WHERE" -t_srs "$SRS_GJ" -nln "$STEM" \
          >/dev/null 2>&1

  if [[ -s "$GJ.tmp" ]]; then
    mv "$GJ.tmp" "$GJ"
    echo "   • GeoJSON  → $(basename "$GJ")  ($(wc -c < "$GJ") B)"
    [[ $GZIP_OUTPUT -eq 1 ]] && gzip -9 -f "$GJ"
    
    local KML_TMP="${KML}.tmp"
    ogr2ogr -f KML "$KML_TMP" "$GPKG" entities \
            -dialect SQLite -where "$WHERE" -t_srs "$SRS_KML" -nln "$STEM" \
            >/dev/null 2>&1
            
    local STYLE_NAME
    case "$STEM" in
      *LOTS*) STYLE_NAME="lotsStyle" ;;
      *CAMINATA*) STYLE_NAME="greenFill" ;;
      *ROW*) STYLE_NAME="rowStyle" ;;
      *FOUNTAIN*|*COMMONAREA*) STYLE_NAME="greenFill" ;;
      *) STYLE_NAME="defaultStyle" ;;
    esac

    # Replace default inline style with reference to shared style document
    # using an absolute URL that includes the style ID.
    sed -e 's|<Style><LineStyle><color>ff0000ff</color></LineStyle><PolyStyle><fill>0</fill></PolyStyle></Style>|<styleUrl>https://lagobello.github.io/lagobello-drawings/web/styles.kml#'${STYLE_NAME}'</styleUrl>|g' \
        -e '/<NetworkLink><Link><href>https:\/\/lagobello.github.io\/lagobello-drawings\/web\/styles.kml<\/href><\/Link><\/NetworkLink>/d' "$KML_TMP" | \
    sed -e '/<gx:drawOrder>/d' \
        -e '/<altitudeMode>clampToGround<\/altitudeMode>/d' \
        -e 's|<Polygon>|<Polygon><altitudeMode>relativeToGround</altitudeMode><gx:altitudeOffset>1</gx:altitudeOffset>|g' \
        -e 's|<LineString>|<LineString><altitudeMode>relativeToGround</altitudeMode><gx:altitudeOffset>1</gx:altitudeOffset>|g' \
        -e 's|<Point>|<Point><altitudeMode>relativeToGround</altitudeMode><gx:altitudeOffset>1</gx:altitudeOffset>|g' \
        -e 's|<kml |<kml xmlns:gx="http://www.google.com/kml/ext/2.2" |' > "$KML"

    rm "$KML_TMP"

    echo "     KML      → $(basename "$KML")  ($(wc -c < "$KML") B)"
  else
    rm -f "$GJ.tmp"
    echo "   • skipping $(basename "$STEM") (0 features)"
  fi
}

# ---------- per-layer hatch exports ----------------------------------------
for LAYER in "${HATCH_LAYERS[@]}"; do
  OUTPUT_STEM="$LAYER"
  if [[ "$LAYER" == "$MISNAMED_STREET" ]]; then
    OUTPUT_STEM="PLAT-HATCH-ROW-S3"
  fi
  export_layer "Layer='${LAYER}' AND SubClasses LIKE '%Hatch%'" "$OUTPUT_STEM"
done

# ---------- non-hatch export -----------------------------------------------
export_layer "SubClasses NOT LIKE '%Hatch%'" "${BASENAME}_non_hatch"

# ---------- done -----------------------------------------------------------
echo "✓ Done.  GeoPackage: $GPKG"
[[ $GZIP_OUTPUT -eq 0 ]] && echo "  (gzip skipped — pass --gzip to create .gz copies)"
