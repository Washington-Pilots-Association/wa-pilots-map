#!/usr/bin/env python3
"""
Process FAA PILOT_BASIC.csv and generate Washington pilot statistics.

Reads: PILOT_BASIC.csv (from FAA Airmen Registry)
Writes: data/wa_pilots.json
"""

import csv
import json
import os
import sys
from collections import Counter
from pathlib import Path

# Ensure we're in the repo root
REPO_ROOT = Path(__file__).parent.parent
os.chdir(REPO_ROOT)


def load_zip_info():
    """Load ZIP code to city/county mapping."""
    zip_to_info = {}
    
    # Try zip_to_city.csv first
    zip_city_file = REPO_ROOT / 'data' / 'zip_to_city.csv'
    if not zip_city_file.exists():
        zip_city_file = REPO_ROOT / 'zip_to_city.csv'  # Legacy location
    
    if zip_city_file.exists():
        with open(zip_city_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                zip_code = row.get('zip', row.get('ZIP', '')).strip()
                city = row.get('city', row.get('CITY', '')).strip()
                county = row.get('county', row.get('COUNTY', '')).strip()
                if zip_code:
                    zip_to_info[zip_code] = {'city': city, 'county': county}
        print(f"Loaded {len(zip_to_info)} ZIP code mappings from {zip_city_file}")
    
    # Enrich with us_geo_data.csv if available
    geo_file = REPO_ROOT / 'data' / 'us_geo_data.csv'
    if not geo_file.exists():
        geo_file = REPO_ROOT / 'us_geo_data.csv'  # Legacy location
    
    if geo_file.exists():
        with open(geo_file, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                if row.get('state_abbr', '').strip() != 'WA':
                    continue
                zip_code = row.get('zipcode', '').strip()
                if not zip_code:
                    continue
                county = row.get('county', '').strip()
                city = row.get('city', '').strip()
                
                if zip_code not in zip_to_info:
                    zip_to_info[zip_code] = {'city': city.title(), 'county': county}
                elif not zip_to_info[zip_code].get('county') and county:
                    zip_to_info[zip_code]['county'] = county
        print(f"Enriched to {len(zip_to_info)} ZIP mappings with us_geo_data.csv")
    
    return zip_to_info


def process_pilots(pilot_file='PILOT_BASIC.csv'):
    """Process pilot data and return counts by ZIP."""
    zip_counts = Counter()
    
    with open(pilot_file, 'r', encoding='latin-1') as f:
        reader = csv.DictReader(f)
        # Strip whitespace from field names (FAA CSV has spaces)
        reader.fieldnames = [name.strip() for name in reader.fieldnames]
        
        for row in reader:
            state = row.get('STATE', '').strip()
            if state == 'WA':
                zip_code = row.get('ZIP CODE', '').strip()[:5]
                if zip_code and zip_code.isdigit() and len(zip_code) == 5:
                    zip_counts[zip_code] += 1
    
    return zip_counts


def calculate_statistics(pilots, zip_counts):
    """Calculate summary statistics."""
    counts = [p['count'] for p in pilots]
    total_pilots = sum(counts)
    total_zips = len(counts)
    
    if total_zips == 0:
        return {
            'total_pilots': 0,
            'total_zips': 0,
            'avg_per_zip': 0,
            'max_count': 0,
            'median_count': 0,
            'top_counties': [],
            'top_zips': []
        }
    
    avg_per_zip = round(total_pilots / total_zips, 1)
    
    sorted_counts = sorted(counts)
    mid = len(sorted_counts) // 2
    if len(sorted_counts) % 2 == 0:
        median = (sorted_counts[mid - 1] + sorted_counts[mid]) / 2
    else:
        median = sorted_counts[mid]
    
    # County totals
    county_counts = Counter()
    for p in pilots:
        county = p['county'] if p['county'] else 'Unknown'
        county_counts[county] += p['count']
    
    return {
        'total_pilots': total_pilots,
        'total_zips': total_zips,
        'avg_per_zip': avg_per_zip,
        'max_count': max(counts),
        'median_count': int(median),
        'top_counties': [
            {'county': county, 'count': count}
            for county, count in county_counts.most_common(15)
        ],
        'top_zips': pilots[:10]
    }


def main():
    print("Processing FAA pilot data for Washington State...")
    
    # Load ZIP info
    zip_to_info = load_zip_info()
    
    # Process pilots
    pilot_file = REPO_ROOT / 'PILOT_BASIC.csv'
    if not pilot_file.exists():
        print(f"ERROR: {pilot_file} not found")
        sys.exit(1)
    
    print(f"Processing {pilot_file}...")
    zip_counts = process_pilots(pilot_file)
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
    
    # Calculate statistics
    summary = calculate_statistics(pilots, zip_counts)
    
    # Build output
    output = {
        'pilots': pilots,
        'summary': summary,
        'metadata': {
            'source': 'FAA Releasable Airmen Database',
            'url': 'https://www.faa.gov/licenses_certificates/airmen_certification/releasable_airmen_download'
        }
    }
    
    # Ensure data directory exists
    data_dir = REPO_ROOT / 'data'
    data_dir.mkdir(exist_ok=True)
    
    # Write output
    output_file = data_dir / 'wa_pilots.json'
    with open(output_file, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"Wrote {output_file}")
    
    # Also write simple by-ZIP text file (for debugging/external use)
    txt_file = data_dir / 'wa_pilots_by_zip.txt'
    with open(txt_file, 'w') as f:
        f.write("ZIP\tCOUNT\tCITY\tCOUNTY\n")
        for p in pilots:
            f.write(f"{p['zip']}\t{p['count']}\t{p['city']}\t{p['county']}\n")
    print(f"Wrote {txt_file}")
    
    print(f"\nSummary:")
    print(f"  Total pilots: {summary['total_pilots']:,}")
    print(f"  ZIP codes: {summary['total_zips']}")
    print(f"  Average per ZIP: {summary['avg_per_zip']}")
    print(f"  Top ZIP: {pilots[0]['zip']} ({pilots[0]['city']}) - {pilots[0]['count']} pilots")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
