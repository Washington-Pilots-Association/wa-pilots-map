# Washington Pilots Heat Map

Interactive visualization of FAA-registered pilots in Washington State by ZIP code, featuring a VFR sectional chart base map.

## Data Sources

- **Pilot Data**: [FAA Releasable Airmen Database](https://www.faa.gov/licenses_certificates/airmen_certification/releasable_airmen_download)
- **VFR Sectional**: [FAA Seattle Sectional Chart](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/vfr/)
- **ZIP Code Boundaries**: US Census ZCTA shapefiles

## Automated Updates

The data is automatically updated weekly via a systemd timer:

- **Schedule**: Every Sunday at 3:00 AM UTC
- **Timer**: `wa-pilots-update.timer`
- **Service**: `wa-pilots-update.service`

### Manual Update

To manually trigger an update:

```bash
# Run the update script directly
./update_data.sh

# Or trigger via systemd
sudo systemctl start wa-pilots-update.service

# Force re-download of sectional chart
./update_data.sh --force-sectional
```

### Check Timer Status

```bash
# View timer status and next run time
systemctl list-timers wa-pilots-update.timer

# View recent logs
journalctl -u wa-pilots-update.service -n 50
```

## Files

| File | Description |
|------|-------------|
| `index.html` | Main interactive map page |
| `update_data.sh` | Main update script (downloads FAA data, processes stats) |
| `process_sectional.sh` | Processes VFR sectional GeoTIFF into web tiles |
| `wa_pilots_full.json` | Generated pilot data with statistics |
| `wa_pilots_by_zip.txt` | Simple tab-separated pilot counts |
| `wa_zip_geo_simple.json` | Simplified ZIP code boundaries for fast loading |
| `sectional-tiles/` | Generated VFR sectional map tiles |

## Update Process

The `update_data.sh` script performs these steps:

1. **Download FAA Airmen Database** - Downloads the latest PILOT_BASIC.csv from FAA
2. **Check VFR Sectional** - Compares chart expiration dates, downloads new chart if expired
3. **Process Sectional** - If new chart downloaded, reprojects and generates tiles
4. **Extract WA Pilots** - Filters WA state pilots, counts by ZIP code
5. **Generate Statistics** - Calculates totals, averages, county breakdowns
6. **Update JSON** - Writes wa_pilots_full.json for the heat map

## VFR Chart Cycle

FAA VFR sectional charts are updated every 56 days. The script checks the chart's expiration date from metadata and automatically downloads updates when available.

## Dependencies

- Python 3
- GDAL (`gdalwarp`, `gdal2tiles.py`)
- curl, unzip

## License

FAA aeronautical data is public domain. This visualization is provided for informational purposes only.
