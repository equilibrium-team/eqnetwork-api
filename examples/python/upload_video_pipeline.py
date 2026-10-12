#!/usr/bin/env python3
"""
EQ Network Automated Video Ingest & Approval Pipeline
=====================================================
Demonstrates:
  1. Authenticating to EQ Network API and obtaining SessionGuid
  2. Resolving or creating the destination Channel (Collection)
  3. Chunked upload of local video file (Upload2_Begin -> Upload2_UploadChunk -> Upload2_Complete)
  4. Registering ContentFile in channel with metadata (Upload2_CreateContentFile)
  5. Polling ContentFile_GetNode until video encoding & review status are ready
"""

import os
import sys
import math
import time
import uuid
import xml.etree.ElementTree as ET
import requests

BASE_URL = os.getenv("EQ_API_URL", "https://eqnetwork.com/sd")
USERNAME = os.getenv("EQ_USERNAME", "test222")
PASSWORD = os.getenv("EQ_PASSWORD", "fEkcow-majdyh-diggi5")
DEFAULT_CHUNK_SIZE = 2 * 1024 * 1024  # 2MB chunks


def create_session(username, password):
    """Authenticate and extract SessionGuid from XML response."""
    url = f"{BASE_URL}/CreateSession.aspx"
    payload = {"UserName": username, "Password": password}
    response = requests.post(url, data=payload, timeout=30)
    response.raise_for_status()

    root = ET.fromstring(response.text)
    session_guid = root.findtext("SessionGuid")
    if not session_guid:
        error = root.findtext("Error") or "Authentication failed"
        raise RuntimeError(f"Login failed: {error}")

    user_elem = root.find("User")
    user_id = user_elem.attrib.get("UserId", "") if user_elem is not None else ""
    verified = user_elem.attrib.get("Verified", "") if user_elem is not None else ""

    print(f"✓ Authenticated as '{username}' (UserId: {user_id}, Verified: {verified})")
    print(f"✓ SessionGuid: {session_guid}")
    return session_guid


def get_or_create_channel(session_guid, channel_name="Automated Ingest Channel"):
    """Finds existing channel or creates a new one."""
    # List channels
    list_url = f"{BASE_URL}/Api2.0/User_ListCollections.aspx"
    payload = {
        "SessionGuid": session_guid,
        "Client": "PythonScript",
        "User_CollectionTypeId": "2",
        "IncludeEmpty": "y",
        "IncludeContentFiles": "N",
        "Start": "1",
        "End": "50",
        "OrderBy": "Recent",
    }
    res = requests.post(list_url, data=payload, timeout=30)
    if res.ok:
        root = ET.fromstring(res.text)
        collections = root.findall(".//Collection")
        for col in collections:
            if col.attrib.get("Name") == channel_name:
                col_id = col.attrib.get("CollectionId")
                print(f"✓ Found existing channel '{channel_name}' (ID: {col_id})")
                return col_id

    # Create channel if not found
    create_url = f"{BASE_URL}/Api2.0/Collection_Create.aspx"
    create_payload = {
        "SessionGuid": session_guid,
        "Name": channel_name,
        "Description": "Channel created via Python Ingest Pipeline",
        "Categories": "Technology",
        "Private": "N",
        "IsPrivate": "false",
    }
    create_res = requests.post(create_url, data=create_payload, timeout=30)
    create_res.raise_for_status()
    create_root = ET.fromstring(create_res.text)
    new_id = create_root.findtext("CollectionId")
    if not new_id:
        raise RuntimeError(f"Channel creation failed: {create_res.text}")

    print(f"✓ Created new channel '{channel_name}' (ID: {new_id})")
    return new_id


def upload_video_file(session_guid, file_path, collection_id, video_title=None, category="Technology"):
    """Executes full chunked upload pipeline for a local video."""
    if not os.path.exists(file_path):
        raise FileNotFoundError(f"File not found: {file_path}")

    file_size = os.path.getsize(file_path)
    file_name = os.path.basename(file_path)
    title = video_title or file_name
    device_id = str(uuid.uuid4())
    total_chunks = max(1, math.ceil(file_size / DEFAULT_CHUNK_SIZE))

    print(f"\n--- Starting Video Ingestion: {file_name} ({file_size / 1024 / 1024:.2f} MB, {total_chunks} chunks) ---")

    # Step 1: Upload2_Begin
    begin_url = f"{BASE_URL}/Api2.0/Upload2_Begin.aspx"
    begin_data = {
        "SessionGuid": session_guid,
        "Name": file_name,
        "OriginalFilepath": file_name,
        "FileSize": file_size,
        "PreferredChunkSize": DEFAULT_CHUNK_SIZE,
        "NumberOfChunks": total_chunks,
        "DeviceIdentifier": device_id,
    }
    begin_res = requests.post(begin_url, data=begin_data, timeout=30)
    begin_res.raise_for_status()
    begin_root = ET.fromstring(begin_res.text)
    upload_elem = begin_root.find("Upload")
    if upload_elem is None:
        raise RuntimeError(f"Upload initialization failed: {begin_res.text}")

    upload_id = upload_elem.attrib.get("UploadId")
    print(f"✓ Upload session allocated (UploadId: {upload_id})")

    # Step 2: Upload2_UploadChunk
    chunk_url = f"{BASE_URL}/Api2.0/Upload2_UploadChunk.aspx"
    with open(file_path, "rb") as f:
        for chunk_idx in range(total_chunks):
            offset = chunk_idx * DEFAULT_CHUNK_SIZE
            chunk_data = f.read(DEFAULT_CHUNK_SIZE)
            actual_size = len(chunk_data)

            files = {"Data": ("blob", chunk_data, "application/octet-stream")}
            data = {
                "SessionGuid": session_guid,
                "UploadId": upload_id,
                "ChunkOffset": offset,
                "ChunkSize": actual_size,
            }

            chunk_res = requests.post(chunk_url, data=data, files=files, timeout=60)
            chunk_res.raise_for_status()
            progress = ((chunk_idx + 1) / total_chunks) * 100
            print(f"  • Uploaded chunk {chunk_idx + 1}/{total_chunks} ({progress:.1f}%)")

    # Step 3: Upload2_Complete
    complete_url = f"{BASE_URL}/Api2.0/Upload2_Complete.aspx"
    complete_res = requests.post(complete_url, data={"SessionGuid": session_guid, "UploadId": upload_id}, timeout=60)
    complete_res.raise_for_status()
    print("✓ Chunks assembled successfully on media server")

    # Step 4: Upload2_CreateContentFile
    create_cf_url = f"{BASE_URL}/Api2.0/Upload2_CreateContentFile.aspx"
    create_cf_data = {
        "SessionGuid": session_guid,
        "UploadId": upload_id,
        "CollectionId": collection_id,
        "Name": title,
        "Description": f"Uploaded automatically via EQ Network Ingest Pipeline at {time.ctime()}",
        "Categories": category,
        "Keywords": "automated,pipeline,api",
    }
    cf_res = requests.post(create_cf_url, data=create_cf_data, timeout=60)
    cf_res.raise_for_status()
    cf_root = ET.fromstring(cf_res.text)
    content_file_id = cf_root.findtext("ContentFileId")
    if not content_file_id:
        raise RuntimeError(f"Failed to create ContentFile: {cf_res.text}")

    print(f"✓ Video registered in channel (ContentFileId: {content_file_id})")

    # Step 5: Poll ContentFile_GetNode for encoding / review status
    print("\n--- Polling Transcode and Review Status ---")
    node_url = f"{BASE_URL}/Api2.0/ContentFile_GetNode.aspx"
    for attempt in range(10):
        time.sleep(3)
        node_res = requests.post(node_url, data={"SessionGuid": session_guid, "ContentFileId": content_file_id}, timeout=30)
        if node_res.ok:
            node_root = ET.fromstring(node_res.text)
            cf_node = node_root.find(".//ContentFile")
            if cf_node is not None:
                active = cf_node.attrib.get("Active", "")
                mux_key = cf_node.attrib.get("CurrentMuxKey", "")
                view_url = cf_node.attrib.get("OriginalUrl", "")
                print(f"  • Attempt {attempt + 1}: Active={active}, MuxKey={mux_key or 'Processing...'}")
                if active == "True":
                    print(f"\n🎉 Video is READY & APPROVED for playback!")
                    print(f"   Watch URL: https://eqnetwork.com/watch?v={content_file_id}")
                    return content_file_id

    print(f"✓ Video registered (ContentFileId: {content_file_id}), background encoding underway.")
    return content_file_id


if __name__ == "__main__":
    session = create_session(USERNAME, PASSWORD)
    channel = get_or_create_channel(session, "API Automation Ingest")
    print(f"\nReady to upload videos into channel: {channel}")
    print("Usage in your scripts: upload_video_file(session, 'my_video.mp4', channel)")
