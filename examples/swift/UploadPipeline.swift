import Foundation

/**
 * EQ Network Video Ingest & Approval Pipeline (Swift / Apple Platforms)
 * Supports iOS, iPadOS, and macOS background video uploads.
 */

public class EQNetworkPipeline {
    private let baseURL: URL
    private let session = URLSession.shared

    public init(baseURL: URL = URL(string: "https://eqnetwork.com/sd")!) {
        self.baseURL = baseURL
    }

    public func createSession(username: String, password: String) async throws -> String {
        let endpoint = baseURL.appendingPathComponent("CreateSession.aspx")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "UserName=\(username)&Password=\(password)"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let xmlString = String(data: data, encoding: .utf8) ?? ""
        if let rangeStart = xmlString.range(of: "<SessionGuid>"),
           let rangeEnd = xmlString.range(of: "</SessionGuid>") {
            let sessionGuid = String(xmlString[rangeStart.upperBound..<rangeEnd.lowerBound])
            return sessionGuid
        }

        throw NSError(domain: "EQNetwork", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse SessionGuid: \(xmlString)"])
    }

    public func uploadVideo(sessionGuid: String, fileURL: URL, collectionId: String, title: String) async throws -> String {
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let fileName = fileURL.lastPathComponent
        let chunkSize = 2 * 1024 * 1024 // 2MB
        let totalChunks = max(1, Int(ceil(Double(fileSize) / Double(chunkSize))))

        // 1. Upload2_Begin
        let beginURL = baseURL.appendingPathComponent("Api2.0/Upload2_Begin.aspx")
        var beginReq = URLRequest(url: beginURL)
        beginReq.httpMethod = "POST"
        beginReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let beginBody = "SessionGuid=\(sessionGuid)&Name=\(fileName)&OriginalFilepath=\(fileName)&FileSize=\(fileSize)&PreferredChunkSize=\(chunkSize)&NumberOfChunks=\(totalChunks)&DeviceIdentifier=\(UUID().uuidString)"
        beginReq.httpBody = beginBody.data(using: .utf8)

        let (beginData, _) = try await session.data(for: beginReq)
        let beginXml = String(data: beginData, encoding: .utf8) ?? ""

        guard let uploadIdRange = beginXml.range(of: "UploadId=\"") else {
            throw NSError(domain: "EQNetwork", code: -1, userInfo: [NSLocalizedDescriptionKey: "Upload2_Begin failed: \(beginXml)"])
        }
        let afterUploadId = beginXml[uploadIdRange.upperBound...]
        guard let quoteRange = afterUploadId.range(of: "\"") else {
            throw NSError(domain: "EQNetwork", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse UploadId"])
        }
        let uploadId = String(afterUploadId[..<quoteRange.lowerBound])
        print("✓ Upload session allocated (UploadId: \(uploadId))")

        // 2. Upload chunks sequentially
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        for chunkIndex in 0..<totalChunks {
            let offset = chunkIndex * chunkSize
            let chunkData = fileHandle.readData(ofLength: chunkSize)

            let chunkURL = baseURL.appendingPathComponent("Api2.0/Upload2_UploadChunk.aspx")
            var chunkReq = URLRequest(url: chunkURL)
            chunkReq.httpMethod = "POST"

            let boundary = UUID().uuidString
            chunkReq.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var bodyData = Data()
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"SessionGuid\"\r\n\r\n\(sessionGuid)\r\n".data(using: .utf8)!)

            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"UploadId\"\r\n\r\n\(uploadId)\r\n".data(using: .utf8)!)

            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"ChunkOffset\"\r\n\r\n\(offset)\r\n".data(using: .utf8)!)

            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"ChunkSize\"\r\n\r\n\(chunkData.count)\r\n".data(using: .utf8)!)

            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"Data\"; filename=\"blob\"\r\n".data(using: .utf8)!)
            bodyData.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            bodyData.append(chunkData)
            bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

            chunkReq.httpBody = bodyData
            let (_, chunkRes) = try await session.data(for: chunkReq)
            guard (chunkRes as? HTTPURLResponse)?.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            print("  • Uploaded chunk \(chunkIndex + 1)/\(totalChunks)")
        }

        // 3. Upload2_Complete
        let completeURL = baseURL.appendingPathComponent("Api2.0/Upload2_Complete.aspx")
        var completeReq = URLRequest(url: completeURL)
        completeReq.httpMethod = "POST"
        completeReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        completeReq.httpBody = "SessionGuid=\(sessionGuid)&UploadId=\(uploadId)".data(using: .utf8)
        let (_, _) = try await session.data(for: completeReq)
        print("✓ Chunks assembled successfully")

        // 4. Upload2_CreateContentFile
        let createURL = baseURL.appendingPathComponent("Api2.0/Upload2_CreateContentFile.aspx")
        var createReq = URLRequest(url: createURL)
        createReq.httpMethod = "POST"
        createReq.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let createBody = "SessionGuid=\(sessionGuid)&UploadId=\(uploadId)&CollectionId=\(collectionId)&Name=\(title)&Categories=Technology"
        createReq.httpBody = createBody.data(using: .utf8)
        let (createData, _) = try await session.data(for: createReq)
        let createXml = String(data: createData, encoding: .utf8) ?? ""

        guard let cfStart = createXml.range(of: "<ContentFileId>"),
              let cfEnd = createXml.range(of: "</ContentFileId>") else {
            throw NSError(domain: "EQNetwork", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create ContentFile: \(createXml)"])
        }
        let contentFileId = String(createXml[cfStart.upperBound..<cfEnd.lowerBound])
        print("✓ Video registered in channel (ContentFileId: \(contentFileId))")
        return contentFileId
    }
}
