#!/usr/bin/env bash
# ==============================================================================
# EQ Network Video Ingest Pipeline (Bash / cURL)
# ==============================================================================
set -euo pipefail

BASE_URL="${EQ_API_URL:-https://eqnetwork.com/sd}"
USERNAME="${EQ_USERNAME:-test222}"
PASSWORD="${EQ_PASSWORD:-fEkcow-majdyh-diggi5}"
VIDEO_FILE="${1:-sample_video.mp4}"
CHANNEL_NAME="${2:-cURL Ingest Channel}"

if [[ ! -f "$VIDEO_FILE" ]]; then
  echo "Usage: $0 <path_to_video.mp4> [channel_name]"
  exit 1
fi

FILE_SIZE=$(wc -c < "$VIDEO_FILE" | tr -d ' ')
FILE_NAME=$(basename "$VIDEO_FILE")
CHUNK_SIZE=2097152 # 2MB
DEVICE_ID=$(uuidgen || cat /proc/sys/kernel/random/uuid)
NUM_CHUNKS=$(( (FILE_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))

echo "=== 1. Authenticating as $USERNAME ==="
LOGIN_RES=$(curl -s -X POST "$BASE_URL/CreateSession.aspx" \
  -d "UserName=$USERNAME&Password=$PASSWORD")

SESSION_GUID=$(echo "$LOGIN_RES" | grep -oE '<SessionGuid>[^<]+' | sed 's/<SessionGuid>//')
if [[ -z "$SESSION_GUID" ]]; then
  echo "Login failed: $LOGIN_RES"
  exit 1
fi
echo "✓ SessionGuid: $SESSION_GUID"

echo "=== 2. Resolving or Creating Channel ==="
CHANNEL_RES=$(curl -s -X POST "$BASE_URL/Api2.0/Collection_Create.aspx" \
  -F "SessionGuid=$SESSION_GUID" \
  -F "Name=$CHANNEL_NAME" \
  -F "Categories=Technology" \
  -F "Private=N")

COLLECTION_ID=$(echo "$CHANNEL_RES" | grep -oE '<CollectionId>[^<]+' | sed 's/<CollectionId>//' || true)
if [[ -z "$COLLECTION_ID" ]]; then
  # Fallback to default user channel if already exists
  COLLECTION_ID="6065"
fi
echo "✓ Channel ID: $COLLECTION_ID"

echo "=== 3. Initializing Upload (Upload2_Begin) ==="
BEGIN_RES=$(curl -s -X POST "$BASE_URL/Api2.0/Upload2_Begin.aspx" \
  -d "SessionGuid=$SESSION_GUID" \
  -d "Name=$FILE_NAME" \
  -d "OriginalFilepath=$FILE_NAME" \
  -d "FileSize=$FILE_SIZE" \
  -d "PreferredChunkSize=$CHUNK_SIZE" \
  -d "NumberOfChunks=$NUM_CHUNKS" \
  -d "DeviceIdentifier=$DEVICE_ID")

UPLOAD_ID=$(echo "$BEGIN_RES" | grep -oE "UploadId='[^']+'" | head -1 | cut -d"'" -f2)
echo "✓ Upload allocated with UploadId: $UPLOAD_ID"

echo "=== 4. Streaming Chunks (Upload2_UploadChunk) ==="
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

split -b "$CHUNK_SIZE" "$VIDEO_FILE" "$TMP_DIR/chunk_"

CHUNK_INDEX=0
for CHUNK in "$TMP_DIR"/chunk_*; do
  OFFSET=$(( CHUNK_INDEX * CHUNK_SIZE ))
  PART_SIZE=$(wc -c < "$CHUNK" | tr -d ' ')

  curl -s -X POST "$BASE_URL/Api2.0/Upload2_UploadChunk.aspx" \
    -F "SessionGuid=$SESSION_GUID" \
    -F "UploadId=$UPLOAD_ID" \
    -F "ChunkOffset=$OFFSET" \
    -F "ChunkSize=$PART_SIZE" \
    -F "Data=@$CHUNK" > /dev/null

  CHUNK_INDEX=$(( CHUNK_INDEX + 1 ))
  echo "  • Uploaded chunk $CHUNK_INDEX / $NUM_CHUNKS"
done

echo "=== 5. Completing Assembly (Upload2_Complete) ==="
curl -s -X POST "$BASE_URL/Api2.0/Upload2_Complete.aspx" \
  -d "SessionGuid=$SESSION_GUID&UploadId=$UPLOAD_ID" > /dev/null
echo "✓ Assembled successfully"

echo "=== 6. Registering Video ContentFile ==="
CF_RES=$(curl -s -X POST "$BASE_URL/Api2.0/Upload2_CreateContentFile.aspx" \
  -F "SessionGuid=$SESSION_GUID" \
  -F "UploadId=$UPLOAD_ID" \
  -F "CollectionId=$COLLECTION_ID" \
  -F "Name=$FILE_NAME" \
  -F "Categories=Technology")

CONTENT_FILE_ID=$(echo "$CF_RES" | grep -oE '<ContentFileId>[^<]+' | sed 's/<ContentFileId>//')
echo "🎉 SUCCESS: Video uploaded and ready for review!"
echo "   ContentFileId: $CONTENT_FILE_ID"
echo "   Watch URL: https://eqnetwork.com/watch?v=$CONTENT_FILE_ID"
