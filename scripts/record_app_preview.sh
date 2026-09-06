#!/usr/bin/env bash
# Record a continuous App Store App Preview from the iOS Simulator (real in-app usage).
# Output: H.264 portrait 886x1920 + silent stereo AAC, ~20s, under Calmiles-assets/previews/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ASSETS_ROOT="${CALMILES_ASSETS:-/Users/matt/Developer/Calmiles-assets}"
OUT_DIR="${ASSETS_ROOT}/previews"
RAW_MOV="${OUT_DIR}/raw-sim-preview.mov"
FINAL_MP4="${OUT_DIR}/calmiles-app-preview-iphone67.mp4"
UDID="${SIM_UDID:-F123AA0A-B97B-48CE-AABC-72EADBC97850}" # iPhone 16 Plus (6.7")
DERIVED="${REPO_ROOT}/build/DerivedData-apppreview"
SCHEME="Calmiles"
START_SS="${PREVIEW_START_SS:-4.5}"

mkdir -p "${OUT_DIR}" "${REPO_ROOT}/build"
rm -f "${RAW_MOV}" "${FINAL_MP4}"

echo "==> Booting simulator ${UDID}"
xcrun simctl bootstatus "${UDID}" -b >/dev/null
xcrun simctl uninstall "${UDID}" studio.botland.calmiles 2>/dev/null || true

echo "==> build-for-testing"
xcodebuild -project "${REPO_ROOT}/Calmiles.xcodeproj" -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "${DERIVED}" -configuration Debug \
  build-for-testing | tee "${REPO_ROOT}/build/apppreview-build.log" | tail -20
grep -q 'BUILD SUCCEEDED' "${REPO_ROOT}/build/apppreview-build.log"

echo "==> Starting simctl video recording"
xcrun simctl io "${UDID}" recordVideo --codec=h264 --force "${RAW_MOV}" &
REC_PID=$!
sleep 1.2

cleanup() {
  if kill -0 "${REC_PID}" 2>/dev/null; then
    echo "==> Stopping recording (pid ${REC_PID})"
    kill -SIGINT "${REC_PID}" 2>/dev/null || true
    wait "${REC_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "==> Running App Preview UI journey"
set +e
xcodebuild -project "${REPO_ROOT}/Calmiles.xcodeproj" -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath "${DERIVED}" -configuration Debug \
  -only-testing:"CalmilesUITests/AppPreviewUITests/testRecordAppPreviewJourney" \
  test-without-building | tee "${REPO_ROOT}/build/apppreview-test.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e

sleep 0.8
cleanup
trap - EXIT
sleep 1

DUR=$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "${RAW_MOV}" | head -1)
echo "raw_duration=${DUR}s"
python3 -c "d=float('${DUR}'); assert d>=18, f'Recording too short ({d}s)'"

echo "==> Encoding App Preview H.264 886x1920 + stereo AAC (~20s)"
# ASC rejects mute files with MOV_RESAVE_STEREO — include silent stereo AAC.
ffmpeg -y -ss "${START_SS}" -i "${RAW_MOV}" \
  -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=44100 \
  -t 20 \
  -vf "scale=886:1920:force_original_aspect_ratio=decrease,pad=886:1920:(ow-iw)/2:(oh-ih)/2,fps=30,setsar=1,format=yuv420p" \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p \
  -r 30 -b:v 10M -maxrate 12M -bufsize 20M \
  -c:a aac -b:a 256k -ac 2 -ar 44100 \
  -shortest -movflags +faststart \
  "${FINAL_MP4}"

ffprobe -v error -show_entries format=duration,size \
  -show_entries stream=codec_type,codec_name,width,height,channels,sample_rate,avg_frame_rate \
  -of default=nw=1 "${FINAL_MP4}"
ls -lh "${FINAL_MP4}"
echo "FINAL=${FINAL_MP4}"
exit "${TEST_STATUS}"
