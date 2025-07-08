#!/usr/bin/env bash
# --------------------------------------------------------------------
# build_all_layers.sh  –  batch driver for build_layers.sh
#
# Processes two DXF files stored in  ../archive/vitto/   relative
# to this script, writing GeoJSON + KML (and optional .gz) into
# the repo-root  web/  directory.
#
# usage examples:
#   ./scripts/build_all_layers.sh
#   ./scripts/build_all_layers.sh --gzip
# --------------------------------------------------------------------
set -euo pipefail

# Absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(realpath "${SCRIPT_DIR}/..")"
BUILD_SCRIPT="${SCRIPT_DIR}/build_layers.sh"

CAD_FILES=(
  "${ROOT_DIR}/archive/vitto/LagoBello-PLANSC-VITTO-20250702.dxf"
  "${ROOT_DIR}/archive/vitto/lago-sec1sec2-map-vitto-20250623-RevA.dxf"
)

# Ensure top-level web/ exists
mkdir -p "${ROOT_DIR}/web"

for CAD in "${CAD_FILES[@]}"; do
  echo "=== Processing $(basename "$CAD") ==="
  # run build_layers.sh from repo root so WEBDIR=web points there
  ( cd "${ROOT_DIR}" && "${BUILD_SCRIPT}" "${CAD}" "$@" )
done
