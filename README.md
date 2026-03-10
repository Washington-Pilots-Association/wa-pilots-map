# Washington Pilots Heat Map

Interactive visualization of FAA-registered pilots in Washington State by ZIP code, featuring a VFR sectional chart base map.

**Live Site:** [washington-pilots-association.github.io/wa-pilots-map](https://washington-pilots-association.github.io/wa-pilots-map/)

![WPA Pilots Map](https://img.shields.io/badge/WPA-Pilots%20Map-green)

## Features

- 🗺️ Interactive heat map of pilot density by ZIP code
- ✈️ FAA VFR Sectional Chart overlay
- 🔴 WPA Chapter locations with meeting info
- 📊 County and ZIP code statistics
- 📱 Mobile-responsive design
- 🔄 Weekly automated data updates

## Data Sources

| Data | Source | Update Frequency |
|------|--------|------------------|
| Pilot Data | [FAA Releasable Airmen Database](https://www.faa.gov/licenses_certificates/airmen_certification/releasable_airmen_download) | Weekly (automated) |
| VFR Sectional | [FAA Seattle Sectional Chart](https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/vfr/) | Every 56 days |
| ZIP Boundaries | US Census ZCTA shapefiles | Static |
| WPA Chapters | Manual maintenance | As needed |

## Repository Structure

```
├── index.html              # Main interactive map page
├── wpa_logo.png            # WPA logo
├── data/
│   ├── wa_pilots.json      # Pilot counts and statistics
│   ├── wa_zip_geo_simple.json  # ZIP code boundaries (GeoJSON)
│   ├── wpa_chapters.json   # WPA chapter locations (GeoJSON)
│   ├── zip_to_city.csv     # ZIP to city/county mapping
│   └── sectional_metadata.json  # Chart version info
├── scripts/
│   ├── process_pilots.py   # FAA data processing
│   └── update_sectional.sh # Sectional chart processor
├── sectional-tiles/        # Generated map tiles (git-ignored, built in CI)
└── .github/workflows/
    ├── update-data.yml     # Weekly FAA data update
    ├── deploy-pages.yml    # GitHub Pages deployment
    └── update-chapters.yml # Manual chapter updates
```

## GitHub Actions Workflows

### 1. Update Pilot Data (`update-data.yml`)
- **Schedule:** Weekly on Sundays at 6:00 AM UTC
- **Trigger:** Manual via workflow_dispatch
- **Actions:**
  - Downloads latest FAA Airmen Registry
  - Extracts Washington pilot data
  - Generates statistics JSON
  - Checks for sectional chart updates
  - Commits changes automatically

### 2. Deploy to GitHub Pages (`deploy-pages.yml`)
- **Trigger:** On push to main branch
- **Actions:**
  - Builds static site
  - Deploys to GitHub Pages

### 3. Update Chapters (`update-chapters.yml`)
- **Trigger:** Manual only
- **Actions:**
  - Validates chapter GeoJSON
  - Commits any changes

## Development

### Local Development

```bash
# Clone the repository
git clone https://github.com/Washington-Pilots-Association/wa-pilots-map.git
cd wa-pilots-map

# Serve locally
python3 -m http.server 8000
# or
busybox httpd -f -p 8000 -h .

# Open http://localhost:8000
```

### Manual Data Update

```bash
# Download FAA data
curl -o airmen.zip https://registry.faa.gov/database/ReleasableAirmen.zip
unzip -j airmen.zip PILOT_BASIC.csv

# Process
python3 scripts/process_pilots.py
```

### Updating WPA Chapters

Edit `data/wpa_chapters.json` directly. Each chapter is a GeoJSON Feature:

```json
{
  "type": "Feature",
  "properties": {
    "name": "Chapter Name",
    "airport": "Airport Name (ICAO)",
    "meeting": "Meeting schedule",
    "contact": "contact@email.com",
    "inactive": false
  },
  "geometry": {
    "type": "Point",
    "coordinates": [-122.0000, 47.0000]
  }
}
```

## Deployment Options

### GitHub Pages (Recommended)
1. Enable GitHub Pages in repository settings
2. Set source to "GitHub Actions"
3. Site deploys automatically on push

### Custom Domain
1. Add CNAME file with your domain
2. Configure DNS to point to GitHub Pages
3. Enable HTTPS in repository settings

### Embed in WIX (wpaflys.org)
```html
<iframe 
  src="https://washington-pilots-association.github.io/wa-pilots-map/" 
  width="100%" 
  height="700px"
  frameborder="0">
</iframe>
```

## License

FAA aeronautical data is public domain. This visualization is provided for informational purposes only.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Submit a pull request

---

*Maintained by [Washington Pilots Association](https://wpaflys.org)*

