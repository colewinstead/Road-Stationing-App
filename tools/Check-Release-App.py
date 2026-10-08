#!/usr/bin/env python3
"""Check an unsigned Release .app or .xcarchive before distribution."""
import plistlib
import subprocess
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: tools/Check-Release-App.py PATH_TO_RELEASE_APP_OR_ARCHIVE")
app = Path(sys.argv[1])
if app.suffix == '.xcarchive':
    app = app / 'Products/Applications/RoadStationApp.app'
info = plistlib.loads((app / 'Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.colewinstead.RoadStationApp'
assert info['CFBundleShortVersionString'] == '1.0'
assert str(info['CFBundleVersion']).isdigit()
assert info['ITSAppUsesNonExemptEncryption'] is False
assert (app / 'Assets.car').is_file()
assert info.get('CFBundleIcons', {}).get('CFBundlePrimaryIcon', {}).get('CFBundleIconName') == 'AppIcon'
manifest = plistlib.loads((app / 'PrivacyInfo.xcprivacy').read_bytes())
assert manifest['NSPrivacyTracking'] is False
assert manifest['NSPrivacyCollectedDataTypes'] == []
assert manifest['NSPrivacyAccessedAPITypes'] == [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp', 'NSPrivacyAccessedAPITypeReasons': ['C617.1', '3B52.1']}]
assert 'The MIT License' in (app / 'Acknowledgments.txt').read_text()
assert list(app.rglob('proj.db')), 'Missing projection database'
assert not any(p.suffix.lower() in {'.xml', '.landxml', '.csv'} for p in app.rglob('*')), 'Unexpected validation/sample data in app'
strings = subprocess.check_output(['strings', str(app / info['CFBundleExecutable'])]).decode(errors='replace')
for marker in ['ROADSTATION_TEST_STORAGE', 'injected-latitude', 'Synthetic developer samples']:
    assert marker not in strings, f'Developer control in Release: {marker}'
print(f'Release packaging checks passed: {app}, version {info["CFBundleShortVersionString"]} ({info["CFBundleVersion"]})')
