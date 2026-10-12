# EQ Network API & SDKs

Official public API documentation, OpenAPI specifications, and integration SDKs for the [EQ Network](https://eqnetwork.com) video platform by Equilibrium.

[![Website](https://img.shields.io/badge/Web-eqnetwork.com-00d2ff.svg)](https://eqnetwork.com)
[![Stage](https://img.shields.io/badge/Stage-stage.eqnetwork.com-7928ca.svg)](https://stage.eqnetwork.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Table of Contents

- [Overview](#overview)
- [Base URLs & Environments](#base-urls--environments)
- [Authentication & Sessions](#authentication--sessions)
- [Video Upload & Approval Pipeline](#video-upload--approval-pipeline)
  - [Step 1: Initialize Upload (`Upload2_Begin.aspx`)](#step-1-initialize-upload)
  - [Step 2: Upload File Chunks (`Upload2_UploadChunk.aspx`)](#step-2-upload-file-chunks)
  - [Step 3: Finalize Upload (`Upload2_Complete.aspx`)](#step-3-finalize-upload)
  - [Step 4: Create Content File & Attach to Channel (`Upload2_CreateContentFile.aspx`)](#step-4-create-content-file)
  - [Step 5: Poll Status & Review/Approval State (`ContentFile_GetNode.aspx`)](#step-5-poll-status--reviewapproval-state)
- [Channel & Collection Management](#channel--collection-management)
  - [List Channels (`User_ListCollections.aspx`)](#list-channels)
  - [Create Channel (`Collection_Create.aspx`)](#create-channel)
  - [Update Channel (`Collection_Update.aspx`)](#update-channel)
  - [Delete Channel (`Collection_Delete.aspx`)](#delete-channel)
- [Video Engagement & Social APIs](#video-engagement--social-apis)
- [Code Examples](#code-examples)
- [Legacy SDKs & Downloads](#legacy-sdks--downloads)
- [Support & Community](#support--community)

---

## Overview

The EQ Network API allows developers, automated ingest pipelines, and third-party tools to programmatically:
1. **Authenticate creators** and maintain active session tokens.
2. **Create, configure, and manage channels** (collections).
3. **Upload video files** using robust chunked uploads with automatic resume and integrity verification.
4. **Attach metadata, categories, and thumbnails** to uploaded videos.
5. **Monitor video transcode states, quality mux levels, and review/approval statuses**.
6. **Programmatically share videos, query analytics, and read/post comments**.

---

## Base URLs & Environments

| Environment | Base URL | API Endpoint Prefix |
| :--- | :--- | :--- |
| **Production** | `https://eqnetwork.com` | `https://eqnetwork.com/sd/` |
| **Staging** | `https://stage.eqnetwork.com` | `https://stage.eqnetwork.com/sd/` |

> **Note**: All requests should include the header `Content-Type: application/x-www-form-urlencoded` or `multipart/form-data` as indicated. Responses are returned in standard XML format; use standard XML-to-JSON parsers or xpath queries in your language of choice.

---

## Authentication & Sessions

EQ Network uses session-based authentication identified by a `SessionGuid`.

### 1. Create Session (Login)
* **Method**: `POST`
* **Endpoint**: `/sd/CreateSession.aspx`
* **Content-Type**: `application/x-www-form-urlencoded`

#### Parameters:
| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `UserName` | string | Yes | The user's account username or email address |
| `Password` | string | Yes | The user's account password |

#### Sample Request:
```bash
curl -X POST https://eqnetwork.com/sd/CreateSession.aspx \
  -d "UserName=your_username&Password=your_password"
```

#### Sample Response:
```xml
<CreateSession>
  <SessionGuid>356ca5a6-fff6-45fb-8780-1fe09c615028</SessionGuid>
  <User 
    UserId='3574' 
    UserName='creator1' 
    Email='creator@example.com' 
    Verified='True' 
    Active='True' 
    Followers='0' 
    ChannelFollowers='0' 
  />
  <Following>854</Following>
  <MyCollectionCount>2</MyCollectionCount>
</CreateSession>
```

### 2. Session Keepalive / Check
* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Session_Check.aspx`

#### Parameters:
| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `SessionGuid` | string | Yes | The active session token |
| `Client` | string | No | Client identifier string (e.g. `API+Script`) |

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Session_Check.aspx \
  -d "SessionGuid=356ca5a6-fff6-45fb-8780-1fe09c615028&Client=Web"
```

---

## Video Upload & Approval Pipeline

Uploading video content to EQ Network uses a resilient 5-step chunked ingestion pipeline:

```
[Local Video File]
       │
       ▼
1. Upload2_Begin.aspx  ────────► Allocates UploadId & Chunk Allocation
       │
       ▼
2. Upload2_UploadChunk.aspx ───► Streams 1MB - 2MB binary chunks with Offset
       │
       ▼
3. Upload2_Complete.aspx ──────► Assembles chunks into single media file
       │
       ▼
4. Upload2_CreateContentFile ──► Attaches video to Channel, sets Name & Metadata
       │
       ▼
5. ContentFile_GetNode.aspx ───► Monitors transcode & approval state
```

### Step 1: Initialize Upload
Allocates an upload session on the storage cluster.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Upload2_Begin.aspx`

#### Parameters:
| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `SessionGuid` | string | Yes | Active session GUID |
| `Name` | string | Yes | File display name (e.g. `sample_video.mp4`) |
| `OriginalFilepath` | string | Yes | Original file path or filename |
| `FileSize` | number | Yes | Total file size in bytes |
| `PreferredChunkSize` | number | Yes | Recommended: `1048576` (1MB) or `2097152` (2MB) |
| `NumberOfChunks` | number | Yes | `Math.ceil(FileSize / PreferredChunkSize)` |
| `DeviceIdentifier` | string | Yes | Unique client UUID (e.g. `55312508-65e6-5a2e-6037-ecb78639102c`) |

#### Sample Request:
```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Upload2_Begin.aspx \
  -d "SessionGuid=YOUR_SESSION_GUID" \
  -d "Name=promo_reel.mp4" \
  -d "OriginalFilepath=promo_reel.mp4" \
  -d "FileSize=15728640" \
  -d "PreferredChunkSize=2097152" \
  -d "NumberOfChunks=8" \
  -d "DeviceIdentifier=55312508-65e6-5a2e-6037-ecb78639102c"
```

#### Sample Response:
```xml
<Upload2_Begin>
  <Upload 
    UploadId='38556' 
    Active='True' 
    FileSize='15728640' 
    UploadedSoFar='0' 
    UploadStateId='0' 
    Filename='d264f100-37a0-4d5c-ac44-44cc41c961cd.mp4' 
  />
  <UploadChunks>
    <UploadChunk ChunkOffset='0' ChunkSize='2097152'/>
  </UploadChunks>
</Upload2_Begin>
```

### Step 2: Upload File Chunks
Uploads each chunk as a multipart form data part.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Upload2_UploadChunk.aspx`
* **Content-Type**: `multipart/form-data`

#### Parameters:
| Field | Type | Description |
| :--- | :--- | :--- |
| `SessionGuid` | string | Active session token |
| `UploadId` | string | Upload ID received from Step 1 |
| `ChunkOffset` | number | Byte offset of this chunk (0, 2097152, ...) |
| `ChunkSize` | number | Size of this specific chunk in bytes |
| `Data` | file | Binary chunk data |

#### Sample Request:
```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Upload2_UploadChunk.aspx \
  -F "SessionGuid=YOUR_SESSION_GUID" \
  -F "UploadId=38556" \
  -F "ChunkOffset=0" \
  -F "ChunkSize=2097152" \
  -F "Data=@chunk_00.bin"
```

### Step 3: Finalize Upload
Tells the server that all chunks have been received and triggers server-side assembly.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Upload2_Complete.aspx`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Upload2_Complete.aspx \
  -d "SessionGuid=YOUR_SESSION_GUID&UploadId=38556"
```

### Step 4: Create Content File
Attaches the assembled video to a specific Channel (Collection) with metadata.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Upload2_CreateContentFile.aspx`
* **Content-Type**: `multipart/form-data`

#### Parameters:
| Field | Type | Required | Description |
| :--- | :--- | :---: | :--- |
| `SessionGuid` | string | Yes | Active session GUID |
| `UploadId` | string | Yes | Assembled Upload ID |
| `CollectionId` | string | Yes | Target Channel ID |
| `Name` | string | Yes | Public video title |
| `Description` | string | No | Video description |
| `Categories` | string | Yes | e.g. `Technology,Entertainment` |
| `Keywords` | string | No | Comma-separated search tags |
| `Thumbnail` | file | No | Optional custom thumbnail image (`.jpg`, `.png`) |

#### Sample Request:
```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Upload2_CreateContentFile.aspx \
  -F "SessionGuid=YOUR_SESSION_GUID" \
  -F "UploadId=38556" \
  -F "CollectionId=6065" \
  -F "Name=Platform Overview 2026" \
  -F "Description=Comprehensive demonstration of EQ Network video streaming." \
  -F "Categories=Technology" \
  -F "Keywords=tech,video,streaming,web3"
```

#### Sample Response:
```xml
<Upload2_CreateContentFile>
  <ContentFileId>18942</ContentFileId>
</Upload2_CreateContentFile>
```

### Step 5: Poll Status & Review/Approval State
Verifies the transcode state, available bitrates, and approval flag.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/ContentFile_GetNode.aspx`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/ContentFile_GetNode.aspx \
  -d "SessionGuid=YOUR_SESSION_GUID&ContentFileId=18942"
```

---

## Channel & Collection Management

### List Channels
Returns all channels created by or followed by the user.

* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/User_ListCollections.aspx`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/User_ListCollections.aspx \
  -d "SessionGuid=YOUR_SESSION_GUID" \
  -d "Client=Web" \
  -d "User_CollectionTypeId=2" \
  -d "IncludeEmpty=y" \
  -d "IncludeContentFiles=N" \
  -d "Start=1" \
  -d "End=30" \
  -d "OrderBy=Recent"
```

### Create Channel
* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Collection_Create.aspx`
* **Content-Type**: `multipart/form-data`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Collection_Create.aspx \
  -F "SessionGuid=YOUR_SESSION_GUID" \
  -F "Name=Studio Master Series" \
  -F "Description=Original studio productions and 4K creative streams." \
  -F "Categories=Entertainment,Music" \
  -F "Private=N" \
  -F "IsPrivate=false" \
  -F "Icon=@channel_icon.png"
```

### Update Channel
* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Collection_Update.aspx`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Collection_Update.aspx \
  -F "SessionGuid=YOUR_SESSION_GUID" \
  -F "CollectionId=6065" \
  -F "Name=Studio Master Series (Updated)" \
  -F "Categories=Entertainment" \
  -F "Private=N"
```

### Delete Channel
* **Method**: `POST`
* **Endpoint**: `/sd/Api2.0/Collection_Delete.aspx`

```bash
curl -X POST https://eqnetwork.com/sd/Api2.0/Collection_Delete.aspx \
  -d "SessionGuid=YOUR_SESSION_GUID&CollectionId=6065"
```

---

## Video Engagement & Social APIs

| Action | Endpoint | Description |
| :--- | :--- | :--- |
| **Like Video** | `POST /sd/Api2.0/ContentFile_SocialAdd.aspx` | Add like/upvote to a video |
| **Unlike Video** | `POST /sd/Api2.0/ContentFile_SocialRemove.aspx` | Remove like from a video |
| **Subscribe / Follow Channel** | `POST /sd/FollowCollection.aspx` | Follow a channel |
| **Post Comment** | `POST /sd/Post_Create.aspx` | Post comment under a video |
| **List Comments** | `POST /sd/Post_ListForContentFile.aspx` | Retrieve comments for a video |
| **Generate Share URL** | `POST /sd/eqntv/CreateUrl.aspx` | Generate short link (`eqn.tv`) |

---

## Code Examples

Complete, production-tested automation scripts are available in the [`examples/`](./examples) directory:

* [Python Video Ingest Pipeline (`examples/python/upload_video_pipeline.py`)](./examples/python/upload_video_pipeline.py)
* [TypeScript / Node.js Ingest Pipeline (`examples/nodejs/upload_video_pipeline.ts`)](./examples/nodejs/upload_video_pipeline.ts)
* [cURL Shell Automation Script (`examples/curl/upload_pipeline.sh`)](./examples/curl/upload_pipeline.sh)
* [C# .NET HttpClient Pipeline (`examples/csharp/UploadPipeline.cs`)](./examples/csharp/UploadPipeline.cs)

---

## Legacy SDKs & Downloads

For legacy environments and desktop development:
* **C# SDK**: [Download C# SDK (eqnetwork.zip)](https://eqnetwork.com/developer/CSharpSDK/eqnetwork.zip)
* **Objective-C SDK**: [Download Objective-C Source (eqnetwork-objectivec-source.zip)](https://eqnetwork.com/developer/ObjectiveCSDK/eqnetwork-objectivec-source.zip)
* **Java SDK**: [Download Java SDK (eq-sdk-1.0.jar)](https://eqnetwork.com/developer/JavaSDK/eq-sdk-1.0.jar)

---

## Support & Community

* **Web**: [eqnetwork.com](https://eqnetwork.com)
* **GitHub Issues**: [github.com/equilibrium-team/eqnetwork-api/issues](https://github.com/equilibrium-team/eqnetwork-api/issues)
* **Organization**: [github.com/equilibrium-team](https://github.com/equilibrium-team)
