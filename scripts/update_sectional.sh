#!/bin/bash
#
# update_sectional.sh - Download and process FAA VFR Sectional Chart
#
# Downloads the Seattle Sectional and generates web map tiles.
# FAA updates charts every 56 days.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

echo "Updating VFR Sectional Chart..."

# Try to find the current sectional URL
get_current_sectional_url() {
    # Try FAA XML listing first
    local URL
    URL=$(curl -sSL "https://aeronav.faa.gov/content/aeronav/sectional_files.xml" 2>/dev/null | \
        grep -oP 'https://[^"<>]+Seattle_SEC\.zip' | head -1 || true)
    
    if [[ -n "$URL" ]]; then
        echo "$URL"
        return 0
    fi
    
    # Fallback: try known recent dates (56-day cycle)
    local DATES=(
        "05-15-2025"
        "03-20-2025"
        "01-23-2025"
    )
    
    for DATE in "${DATES[@]}"; do
        local TEST_URL="https://aeronav.faa.gov/visual/${DATE}/sectional-files/Seattle_SEC.zip"
        if curl -sSL --head "$TEST_URL" 2>/dev/null | grep -q "200"; then
            echo "$TEST_URL"
            return 0
        fi
    done
    
    return 1
}

# Get URL
SECTIONAL_URL=$(get_current_sectional_url)
if [[ -z "$SECTIONAL_URL" ]]; then
    echo "ERROR: Could not find sectional chart URL"
    exit 1
fi

echo "Downloading from: $SECTIONAL_URL"

# Download
curl -sSL -o Seattle_SEC.zip "$SECTIONAL_URL"

# Extract
echo "Extracting..."
unzip -o Seattle_SEC.zip -d .

# Find the GeoTIFF
TIFF_FILE=$(find . -maxdepth 1 -name "*.tif" -type f | head -1)
if [[ -z "$TIFF_FILE" ]]; then
    echo "ERROR: No GeoTIFF found after extraction"
    exit 1
fi

echo "Processing $TIFF_FILE..."

# Reproject to Web Mercator
echo "Reprojecting to EPSG:3857..."
gdalwarp -t_srs EPSG:3857 \
    -r bilinear \
    -co COMPRESS=JPEG \
    -co JPEG_QUALITY=85 \
    "$TIFF_FILE" seattle_mercator.tif

# Generate tiles
echo "Generating map tiles..."
rm -rf sectional-tiles
gdal2tiles.py --zoom=5-11 \
    --processes=4 \
    --webviewer=none \
    seattle_mercator.tif sectional-tiles

# Extract metadata
echo "Extracting metadata..."
if [[ -f "Seattle SEC.htm" ]]; then
    EFFECTIVE=$(grep -oP 'dc\.coverage\.t\.min.*?content="\K[0-9]+' "Seattle SEC.htm" | head -1 || echo "")
    EXPIRES=$(grep -oP 'dc\.coverage\.t\.max.*?content="\K[0-9]+' "Seattle SEC.htm" | head -1 || echo "")
    
    # Convert YYYYMMDD to YYYY-MM-DD
    if [[ -n "$EXPIRES" ]]; then
        EXPIRES_FMT="${EXPIRES:0:4}-${EXPIRES:4:2}-${EXPIRES:6:2}"
    else
        EXPIRES_FMT=""
    fi
    
    mkdir -p data
    cat > data/sectional_metadata.json << EOF
{
  "chart": "Seattle Sectional",
  "effective": "$EFFECTIVE",
  "expires": "$EXPIRES_FMT",
  "source_url": "$SECTIONAL_URL",
  "updated": "$(date -Iseconds)"
}
EOF
    echo "Metadata saved to data/sectional_metadata.json"
fi

# Cleanup large intermediate files
echo "Cleaning up..."
rm -f Seattle_SEC.zip seattle_mercator.tif "$TIFF_FILE" "Seattle SEC.htm" "Seattle SEC.tfw" *.vrt

echo "Done! Sectional tiles generated in sectional-tiles/"
