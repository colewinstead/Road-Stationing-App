#!/bin/bash
# Build and exercise the real Files picker plus synthetic developer workflows.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 ]]; then
  echo 'Usage: tools/Test-iOS-Harness.sh SIMULATOR_UDID' >&2
  echo 'Find an available iPhone with: xcrun simctl list devices available' >&2
  exit 2
fi
simulator_id="$1"
output_dir="$PWD/validation-output/phase15"
build_dir="$output_dir/DerivedData"
results_dir="$output_dir/UI-$(date +%Y%m%d-%H%M%S).xcresult"
mkdir -p "$output_dir"
if ! xcrun simctl list devices booted | rg -q "$simulator_id"; then
  xcrun simctl boot "$simulator_id"
fi
xcrun simctl bootstatus "$simulator_id" -b
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj -scheme RoadStationApp \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$simulator_id" "$build_dir/Build/Products/Debug-iphonesimulator/RoadStationApp.app"
app_data_dir="$(xcrun simctl get_app_container "$simulator_id" com.colewinstead.RoadStationApp data)"
mkdir -p "$app_data_dir/Documents"
cp Tests/Fixtures/tangent-only.xml "$app_data_dir/Documents/import-check.landxml"
cp Tests/Fixtures/tangent-only.xml "$app_data_dir/Documents/import-xml.xml"
cp Tests/Fixtures/malformed.xml "$app_data_dir/Documents/malformed.xml"
xcodebuild -project RoadStationApp/RoadStationApp.xcodeproj -scheme RoadStationApp \
  -configuration Debug -destination "platform=iOS Simulator,id=$simulator_id" \
  -derivedDataPath "$build_dir" -resultBundlePath "$results_dir" \
  -parallel-testing-enabled NO -collect-test-diagnostics never \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 \
  -maximum-test-execution-time-allowance 300 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
printf 'Result bundle: %s\n' "$results_dir"
