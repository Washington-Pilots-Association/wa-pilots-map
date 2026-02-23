#!/bin/bash
#
# update_data.sh - Weekly update script for WA Pilots heat map
#
# This script:
# 1. Downloads the latest FAA airmen database
# 2. Checks for VFR sectional chart updates and processes if needed
# 3. Extracts Washington pilot data
# 4. Generates updated statistics and JSON for the heat map
#
# Usage: ./update_data.sh [--force-sectional]
#   --force-sectional: Force re-download and reprocessing of sectional chart
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LOG_FILE="$SCRIPT_DIR/update.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "========================================"
log "Starting WA Pilots data update"
log "========================================"

# Parse arguments
FORCE_SECTIONAL=false
if [[ "$1" == "--force-sectional" ]]; then
    FORCE_SECTIONAL=true
    log "Force sectional update requested"
fi

# ============================================
# Step 1: Download FAA Airmen Database
# ============================================
log "Step 1: Downloading FAA Airmen Database..."

AIRMEN_URL="https://registry.faa.gov/database/ReleasableAirmen.zip"
AIRMEN_ZIP="airmen.zip"

# Check current file date
if [[ -f "$AIRMEN_ZIP" ]]; then
    CURRENT_DATE=$(stat -c %Y "$AIRMEN_ZIP" 2>/dev/null || echo "0")
else
    CURRENT_DATE=0
fi

# Download with retry logic (FAA servers can be slow/unreliable)
log "Downloading from $AIRMEN_URL..."
DOWNLOAD_SUCCESS=false
for ATTEMPT in 1 2 3; do
    log "Download attempt $ATTEMPT of 3..."
    if curl -sSL -o "${AIRMEN_ZIP}.new" \
        --connect-timeout 60 \
        --max-time 600 \
        --retry 3 \
        --retry-delay 10 \
        -z "$AIRMEN_ZIP" \
        "$AIRMEN_URL"; then
        if [[ -f "${AIRMEN_ZIP}.new" && -s "${AIRMEN_ZIP}.new" ]]; then
            mv "${AIRMEN_ZIP}.new" "$AIRMEN_ZIP"
            log "Downloaded new airmen data"
            DOWNLOAD_SUCCESS=true
            break
        else
            rm -f "${AIRMEN_ZIP}.new"
            log "Airmen data is up to date (no new data)"
            DOWNLOAD_SUCCESS=true
            break
        fi
    else
        log "Download attempt $ATTEMPT failed, retrying..."
        rm -f "${AIRMEN_ZIP}.new"
        sleep 30
    fi
done

if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    # If download failed but we have existing data, continue with warning
    if [[ -f "$AIRMEN_ZIP" ]]; then
        log "WARNING: Could not download new airmen data, using existing file"
    else
        log "ERROR: Failed to download airmen data and no existing file found"
        exit 1
    fi
fi

# Extract PILOT_BASIC.csv
log "Extracting PILOT_BASIC.csv..."
if unzip -o -j "$AIRMEN_ZIP" PILOT_BASIC.csv -d .; then
    log "Extracted PILOT_BASIC.csv"
else
    log "ERROR: Failed to extract PILOT_BASIC.csv"
    exit 1
fi

# ============================================
# Step 2: Check VFR Sectional Chart Updates
# ============================================
log "Step 2: Checking VFR Sectional Chart..."

SECTIONAL_URL="https://aeronav.faa.gov/visual/01-23-2025/sectional-files/Seattle_SEC.zip"
SECTIONAL_ZIP="Seattle_SEC.zip"
SECTIONAL_METADATA="Seattle SEC.htm"

# The FAA updates sectional charts every 56 days
# We need to check the VFR chart effective dates page to find current URL

get_current_sectional_url() {
    # Try to determine the current sectional URL from FAA website
    # The URLs follow a pattern: https://aeronav.faa.gov/visual/MM-DD-YYYY/sectional-files/Seattle_SEC.zip
    
    local EDITIONS_PAGE="https://aeronav.faa.gov/content/aeronav/sectional_files.xml"
    local CURRENT_URL
    
    # Try to get the current edition from the XML listing
    CURRENT_URL=$(curl -sSL "$EDITIONS_PAGE" 2>/dev/null | \
        grep -oP 'https://[^"<>]+Seattle_SEC\.zip' | head -1 || true)
    
    if [[ -n "$CURRENT_URL" ]]; then
        echo "$CURRENT_URL"
        return 0
    fi
    
    # Fallback: try the visual charts page
    CURRENT_URL=$(curl -sSL "https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/vfr/" 2>/dev/null | \
        grep -oP 'https://[^"]+Seattle_SEC\.zip' | head -1 || true)
    
    if [[ -n "$CURRENT_URL" ]]; then
        echo "$CURRENT_URL"
        return 0
    fi
    
    # Final fallback: construct URL based on expected cycle dates
    # VFR charts are on a 56-day cycle starting from a known date
    # This is a simplified approach - in production you'd want to calculate the exact date
    local RECENT_DATES=(
        "03-20-2025"
        "01-23-2025"
        "11-26-2024"
    )
    
    for DATE in "${RECENT_DATES[@]}"; do
        local TEST_URL="https://aeronav.faa.gov/visual/${DATE}/sectional-files/Seattle_SEC.zip"
        if curl -sSL --head "$TEST_URL" 2>/dev/null | grep -q "200 OK"; then
            echo "$TEST_URL"
            return 0
        fi
    done
    
    return 1
}

# Get current effective dates from metadata
get_chart_dates() {
    if [[ -f "$SECTIONAL_METADATA" ]]; then
        grep -oP 'dc\.coverage\.t\.max.*?content="\K[0-9]+' "$SECTIONAL_METADATA" | head -1
    fi
}

CURRENT_END_DATE=$(get_chart_dates)
log "Current chart end date: ${CURRENT_END_DATE:-unknown}"

# Check if chart has expired (end date is in the past)
NOW=$(date +%Y%m%d)
CHART_EXPIRED=false
if [[ -n "$CURRENT_END_DATE" && "$CURRENT_END_DATE" < "$NOW" ]]; then
    CHART_EXPIRED=true
    log "Chart has expired (ended $CURRENT_END_DATE), checking for update..."
fi

if [[ "$FORCE_SECTIONAL" == "true" ]] || [[ "$CHART_EXPIRED" == "true" ]]; then
    log "Attempting to download updated sectional chart..."
    
    SECTIONAL_URL=$(get_current_sectional_url)
    if [[ -n "$SECTIONAL_URL" ]]; then
        log "Found sectional URL: $SECTIONAL_URL"
        
        if curl -sSL -o "${SECTIONAL_ZIP}.new" "$SECTIONAL_URL"; then
            if [[ -s "${SECTIONAL_ZIP}.new" ]]; then
                # Check if this is actually a new version
                NEW_MD5=$(md5sum "${SECTIONAL_ZIP}.new" | cut -d' ' -f1)
                if [[ -f "$SECTIONAL_ZIP" ]]; then
                    OLD_MD5=$(md5sum "$SECTIONAL_ZIP" | cut -d' ' -f1)
                else
                    OLD_MD5=""
                fi
                
                if [[ "$NEW_MD5" != "$OLD_MD5" ]]; then
                    mv "${SECTIONAL_ZIP}.new" "$SECTIONAL_ZIP"
                    log "Downloaded new sectional chart"
                    
                    # Extract and process the new chart
                    log "Extracting sectional chart..."
                    unzip -o "$SECTIONAL_ZIP" -d .
                    
                    # Process the GeoTIFF
                    log "Processing sectional chart for web tiles..."
                    ./process_sectional.sh
                else
                    log "Downloaded chart is same as current, skipping"
                    rm -f "${SECTIONAL_ZIP}.new"
                fi
            else
                log "Downloaded file is empty"
                rm -f "${SECTIONAL_ZIP}.new"
            fi
        else
            log "WARNING: Failed to download sectional chart (may not be available yet)"
            rm -f "${SECTIONAL_ZIP}.new"
        fi
    else
        log "WARNING: Could not determine current sectional URL"
    fi
else
    log "Sectional chart is current (expires $CURRENT_END_DATE)"
fi

# ============================================
# Step 3: Extract Washington Pilot Data
# ============================================
log "Step 3: Extracting Washington pilot data..."

python3 << 'PYTHON_SCRIPT'
import csv
import json
from collections import defaultdict, Counter
import sys

print("Processing PILOT_BASIC.csv...")

# Read ZIP to city/county mapping
# File format: ZIP,CITY (no header) or ZIP,CITY,COUNTY with header
zip_to_info = {}
try:
    with open('zip_to_city.csv', 'r') as f:
        first_line = f.readline().strip()
        f.seek(0)
        
        # Check if first line looks like a header
        if first_line.lower().startswith('zip'):
            reader = csv.DictReader(f)
            for row in reader:
                zip_code = row.get('zip', row.get('ZIP', '')).strip()
                city = row.get('city', row.get('CITY', '')).strip()
                county = row.get('county', row.get('COUNTY', '')).strip()
                if zip_code:
                    zip_to_info[zip_code] = {'city': city, 'county': county}
        else:
            # No header, assume ZIP,CITY format
            reader = csv.reader(f)
            for row in reader:
                if len(row) >= 2:
                    zip_code = row[0].strip()
                    city = row[1].strip().title()  # Convert CITY to City
                    county = row[2].strip() if len(row) > 2 else ''
                    if zip_code:
                        zip_to_info[zip_code] = {'city': city, 'county': county}
    print(f"Loaded {len(zip_to_info)} ZIP code mappings")
except FileNotFoundError:
    print("Warning: zip_to_city.csv not found, city/county info will be limited")

# Try to load county info from us_geo_data.csv if available
try:
    with open('us_geo_data.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            state = row.get('state_abbr', '').strip()
            if state != 'WA':
                continue
            zip_code = row.get('zipcode', '').strip()
            if not zip_code:
                continue
            county = row.get('county', '').strip()
            city = row.get('city', '').strip()
            
            # Add or update entry
            if zip_code not in zip_to_info:
                zip_to_info[zip_code] = {'city': city.title(), 'county': county}
            elif not zip_to_info[zip_code].get('county') and county:
                zip_to_info[zip_code]['county'] = county
    print(f"Updated to {len(zip_to_info)} ZIP code mappings with county info")
except (FileNotFoundError, Exception) as e:
    print(f"Note: Could not enrich with us_geo_data.csv: {e}")

# Count pilots by ZIP code
zip_counts = Counter()
try:
    with open('PILOT_BASIC.csv', 'r', encoding='latin-1') as f:
        reader = csv.DictReader(f)
        # Strip whitespace from field names (FAA CSV has spaces)
        reader.fieldnames = [name.strip() for name in reader.fieldnames]
        for row in reader:
            state = row.get('STATE', '').strip()
            if state == 'WA':
                zip_code = row.get('ZIP CODE', '').strip()[:5]  # Take first 5 digits
                if zip_code and zip_code.isdigit() and len(zip_code) == 5:
                    zip_counts[zip_code] += 1
except Exception as e:
    print(f"Error reading PILOT_BASIC.csv: {e}")
    sys.exit(1)

print(f"Found {sum(zip_counts.values())} pilots in {len(zip_counts)} ZIP codes")

# Build pilot data list
pilots = []
for zip_code, count in sorted(zip_counts.items(), key=lambda x: -x[1]):
    info = zip_to_info.get(zip_code, {'city': '', 'county': ''})
    pilots.append({
        'zip': zip_code,
        'count': count,
        'city': info.get('city', ''),
        'county': info.get('county', '')
    })

# Calculate county totals
county_counts = Counter()
for p in pilots:
    county = p['county'] if p['county'] else 'Unknown'
    county_counts[county] += p['count']

# Calculate statistics
counts = [p['count'] for p in pilots]
total_pilots = sum(counts)
total_zips = len(counts)
avg_per_zip = round(total_pilots / total_zips, 1) if total_zips > 0 else 0

sorted_counts = sorted(counts)
if len(sorted_counts) % 2 == 0:
    median = (sorted_counts[len(sorted_counts)//2 - 1] + sorted_counts[len(sorted_counts)//2]) / 2
else:
    median = sorted_counts[len(sorted_counts)//2]

# Build output
output = {
    'pilots': pilots,
    'summary': {
        'total_pilots': total_pilots,
        'total_zips': total_zips,
        'avg_per_zip': avg_per_zip,
        'max_count': max(counts) if counts else 0,
        'median_count': int(median),
        'top_counties': [
            {'county': county, 'count': count}
            for county, count in county_counts.most_common(15)
        ],
        'top_zips': pilots[:10]
    }
}

# Write output
with open('wa_pilots_full.json', 'w') as f:
    json.dump(output, f)

print(f"Wrote wa_pilots_full.json")

# Also write simple by-ZIP text file
with open('wa_pilots_by_zip.txt', 'w') as f:
    for p in pilots:
        f.write(f"{p['zip']}\t{p['count']}\t{p['city']}\t{p['county']}\n")

print(f"Wrote wa_pilots_by_zip.txt")
print("Done!")
PYTHON_SCRIPT

log "Step 3 complete: Generated updated pilot data"

# ============================================
# Step 4: Update index.html date reference
# ============================================
log "Step 4: Updating index.html date reference..."

CURRENT_MONTH=$(date '+%B %Y')
sed -i "s/(.*[0-9]\{4\})/(${CURRENT_MONTH})/g" index.html 2>/dev/null || true
log "Updated date reference to $CURRENT_MONTH"

# ============================================
# Summary
# ============================================
log "========================================"
log "Update complete!"
log "========================================"

# Show summary
PILOT_COUNT=$(python3 -c "import json; d=json.load(open('wa_pilots_full.json')); print(d['summary']['total_pilots'])")
ZIP_COUNT=$(python3 -c "import json; d=json.load(open('wa_pilots_full.json')); print(d['summary']['total_zips'])")

log "Total pilots: $PILOT_COUNT"
log "Total ZIP codes: $ZIP_COUNT"
log "Data files updated:"
log "  - wa_pilots_full.json"
log "  - wa_pilots_by_zip.txt"

if [[ "$CHART_EXPIRED" == "true" ]] || [[ "$FORCE_SECTIONAL" == "true" ]]; then
    log "  - Sectional chart: checked/updated"
fi

log "Update log: $LOG_FILE"
