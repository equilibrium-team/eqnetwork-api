/**
 * EQ Network Video Ingestion & Review Pipeline (TypeScript / Node.js)
 * ==================================================================
 * Requirements: Node.js 18+ (native fetch and FormData support)
 */

import * as fs from 'fs';
import * as path from 'path';
import { randomUUID } from 'crypto';

const BASE_URL = process.env.EQ_API_URL || 'https://eqnetwork.com/sd';
const USERNAME = process.env.EQ_USERNAME || 'test222';
const PASSWORD = process.env.EQ_PASSWORD || 'fEkcow-majdyh-diggi5';
const CHUNK_SIZE = 2 * 1024 * 1024; // 2MB chunks

interface IngestOptions {
  filePath: string;
  channelId: string;
  title?: string;
  category?: string;
}

export async function createSession(username: string, password: string): Promise<string> {
  const params = new URLSearchParams();
  params.append('UserName', username);
  params.append('Password', password);

  const res = await fetch(`${BASE_URL}/CreateSession.aspx`, {
    method: 'POST',
    body: params,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
  });

  const xml = await res.text();
  const sessionMatch = xml.match(/<SessionGuid>([^<]+)<\/SessionGuid>/);
  if (!sessionMatch) {
    throw new Error(`Login failed: ${xml}`);
  }

  const sessionGuid = sessionMatch[1];
  console.log(`✓ Authenticated as ${username} (Session: ${sessionGuid})`);
  return sessionGuid;
}

export async function uploadVideo(sessionGuid: string, opts: IngestOptions): Promise<string> {
  const { filePath, channelId, title = path.basename(filePath), category = 'Technology' } = opts;
  const stats = fs.statSync(filePath);
  const fileSize = stats.size;
  const fileName = path.basename(filePath);
  const totalChunks = Math.max(1, Math.ceil(fileSize / CHUNK_SIZE));
  const deviceId = randomUUID();

  console.log(`\n--- Ingesting ${fileName} (${(fileSize / 1024 / 1024).toFixed(2)} MB, ${totalChunks} chunks) ---`);

  // 1. Upload2_Begin
  const beginParams = new URLSearchParams();
  beginParams.append('SessionGuid', sessionGuid);
  beginParams.append('Name', fileName);
  beginParams.append('OriginalFilepath', fileName);
  beginParams.append('FileSize', fileSize.toString());
  beginParams.append('PreferredChunkSize', CHUNK_SIZE.toString());
  beginParams.append('NumberOfChunks', totalChunks.toString());
  beginParams.append('DeviceIdentifier', deviceId);

  const beginRes = await fetch(`${BASE_URL}/Api2.0/Upload2_Begin.aspx`, {
    method: 'POST',
    body: beginParams,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
  });

  const beginXml = await beginRes.text();
  const uploadIdMatch = beginXml.match(/UploadId='([^']+)'/);
  if (!uploadIdMatch) {
    throw new Error(`Upload initialization failed: ${beginXml}`);
  }
  const uploadId = uploadIdMatch[1];
  console.log(`✓ Session allocated (UploadId: ${uploadId})`);

  // 2. Upload2_UploadChunk
  const fd = fs.openSync(filePath, 'r');
  const buffer = Buffer.alloc(CHUNK_SIZE);

  for (let i = 0; i < totalChunks; i++) {
    const offset = i * CHUNK_SIZE;
    const bytesRead = fs.readSync(fd, buffer, 0, CHUNK_SIZE, offset);
    const chunkData = buffer.subarray(0, bytesRead);

    const form = new FormData();
    form.append('SessionGuid', sessionGuid);
    form.append('UploadId', uploadId);
    form.append('ChunkOffset', offset.toString());
    form.append('ChunkSize', bytesRead.toString());
    form.append('Data', new Blob([chunkData]), 'chunk.bin');

    const chunkRes = await fetch(`${BASE_URL}/Api2.0/Upload2_UploadChunk.aspx`, {
      method: 'POST',
      body: form
    });

    if (!chunkRes.ok) {
      fs.closeSync(fd);
      throw new Error(`Chunk ${i + 1} upload failed`);
    }

    const progress = (((i + 1) / totalChunks) * 100).toFixed(1);
    console.log(`  • Chunk ${i + 1}/${totalChunks} uploaded (${progress}%)`);
  }
  fs.closeSync(fd);

  // 3. Upload2_Complete
  const completeParams = new URLSearchParams();
  completeParams.append('SessionGuid', sessionGuid);
  completeParams.append('UploadId', uploadId);

  await fetch(`${BASE_URL}/Api2.0/Upload2_Complete.aspx`, {
    method: 'POST',
    body: completeParams,
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
  });
  console.log(`✓ Chunks assembled on storage server`);

  // 4. Upload2_CreateContentFile
  const createForm = new FormData();
  createForm.append('SessionGuid', sessionGuid);
  createForm.append('UploadId', uploadId);
  createForm.append('CollectionId', channelId);
  createForm.append('Name', title);
  createForm.append('Categories', category);
  createForm.append('Description', `Ingested via Node.js API pipeline at ${new Date().toISOString()}`);

  const createRes = await fetch(`${BASE_URL}/Api2.0/Upload2_CreateContentFile.aspx`, {
    method: 'POST',
    body: createForm
  });

  const createXml = await createRes.text();
  const cfMatch = createXml.match(/<ContentFileId>([^<]+)<\/ContentFileId>/);
  if (!cfMatch) {
    throw new Error(`ContentFile creation failed: ${createXml}`);
  }

  const contentFileId = cfMatch[1];
  console.log(`✓ Video registered in channel (ContentFileId: ${contentFileId})`);
  console.log(`   Watch URL: https://eqnetwork.com/watch?v=${contentFileId}`);

  return contentFileId;
}
