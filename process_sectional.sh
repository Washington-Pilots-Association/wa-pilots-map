#!/bin/bash
#
# process_sectional.sh - Process VFR sectional chart GeoTIFF into web tiles
#
# This script takes the Seattle SEC.tif and:
# 1. Reprojects to Web Mercator (EPSG:3857)
# 2. Adds alpha channel for transparency
# 3. Generates map tiles for web use
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Processing VFR Sectional Chart..."

INPUT_TIF="Seattle SEC.tif"
MERCATOR_TIF="seattle_mercator.tif"
RGBA_VRT="seattle_rgba.vrt"
TILES_DIR="sectional-tiles"

# Check input file exists
if [[ ! -f "$INPUT_TIF" ]]; then
    echo "ERROR: $INPUT_TIF not found"
    exit 1
fi

# Step 1: Reproject to Web Mercator
echo "Step 1: Reprojecting to Web Mercator..."
gdalwarp -t_srs EPSG:3857 \
    -r bilinear \
    -co COMPRESS=LZW \
    -co TILED=YES \
    -overwrite \
    "$INPUT_TIF" "$MERCATOR_TIF"

echo "Created $MERCATOR_TIF"

# Step 2: Create VRT with alpha channel
echo "Step 2: Creating VRT with alpha channel..."
cat > "$RGBA_VRT" << EOF
<VRTDataset rasterXSize="$(gdalinfo "$MERCATOR_TIF" | grep -oP 'Size is \K[0-9]+')" rasterYSize="$(gdalinfo "$MERCATOR_TIF" | grep -oP 'Size is [0-9]+, \K[0-9]+')">
  <SRS>$(gdalsrsinfo -o wkt "$MERCATOR_TIF")</SRS>
  <GeoTransform>$(gdalinfo "$MERCATOR_TIF" | grep -A1 "Origin" | tail -1 | sed 's/Pixel Size = //' | tr -d '()' | awk -F',' '{print "-424632.18, "$1", 0, 6274861.39, 0, -"$2}')</GeoTransform>
  <VRTRasterBand dataType="Byte" band="1">
    <ColorInterp>Red</ColorInterp>
    <SimpleSource>
      <SourceFilename relativeToVRT="1">$MERCATOR_TIF</SourceFilename>
      <SourceBand>1</SourceBand>
    </SimpleSource>
  </VRTRasterBand>
  <VRTRasterBand dataType="Byte" band="2">
    <ColorInterp>Green</ColorInterp>
    <SimpleSource>
      <SourceFilename relativeToVRT="1">$MERCATOR_TIF</SourceFilename>
      <SourceBand>2</SourceBand>
    </SimpleSource>
  </VRTRasterBand>
  <VRTRasterBand dataType="Byte" band="3">
    <ColorInterp>Blue</ColorInterp>
    <SimpleSource>
      <SourceFilename relativeToVRT="1">$MERCATOR_TIF</SourceFilename>
      <SourceBand>3</SourceBand>
    </SimpleSource>
  </VRTRasterBand>
</VRTDataset>
EOF

echo "Created $RGBA_VRT"

# Step 3: Generate tiles
echo "Step 3: Generating web tiles (this may take several minutes)..."
rm -rf "$TILES_DIR"

gdal2tiles.py \
    --zoom=5-11 \
    --processes=4 \
    --webviewer=none \
    --tmscompatible \
    "$MERCATOR_TIF" "$TILES_DIR"

echo "Created tiles in $TILES_DIR"

# Count tiles
TILE_COUNT=$(find "$TILES_DIR" -name "*.png" | wc -l)
echo "Generated $TILE_COUNT tiles"

echo "Sectional processing complete!"
