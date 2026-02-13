# PRD: File Attachments for Stacks and Tasks

**Status**: ✅ FULLY IMPLEMENTED
**Author**: Victor
**Created**: 2026-01-02
**Last Updated**: 2026-02-13 (implementation complete)
**Implementation**: January 7-18, 2026
**Tickets**: DEQ-71, DEQ-72, DEQ-75, DEQ-77, DEQ-81, DEQ-82, DEQ-83, DEQ-87, DEQ-91

---

## ✅ Implementation Summary

**All core components implemented:**
- ✅ **Attachment Model** (DEQ-71, PR #99) - SwiftData model with relationships
- ✅ **AttachmentService** (DEQ-72, PR #131) - Full CRUD operations
- ✅ **UploadManager** (DEQ-77, PR #134) - Progress tracking, background uploads
- ✅ **File Picker** (DEQ-83, PR #140) - Cross-platform file selection
- ✅ **Stack Attachments UI** (DEQ-81, PR #138) - Attachment section in StackDetailView
- ✅ **Task Attachments UI** (DEQ-82, PR #139) - Attachment section in TaskDetailView
- ✅ **Thumbnails** (DEQ-87, PR #237) - Automatic image thumbnail generation  
- ✅ **Settings** (DEQ-91, PR #147) - Attachment preferences
- ✅ **ProjectorService** (DEQ-75) - Event sourcing support
- ✅ **Tests** - AttachmentServiceTests, UploadManagerTests, DownloadManagerTests

**Status:** Feature complete as of January 18, 2026

---

## Executive Summary

Enable users to attach arbitrary files (images, PDFs, documents, etc.) to Stacks and Tasks. Files are stored in Cloudflare R2 with presigned URL uploads. The feature follows the app's offline-first, event-driven architecture with configurable download behavior and storage quotas.

**Key Decisions:**
- **Max file size**: 50 MB per attachment
- **Storage quota**: 5 GB default (user-configurable)
- **Upload method**: Presigned URLs (client → R2 direct)
- **Download mode**: On-demand by default (user-configurable)
- **Thumbnails**: Client-side generation only
- **File retention**: 30 days after removal before cleanup
- **File types**: No restrictions

---

## 1. Overview

### 1.1 Problem Statement

Users need to attach reference materials (documents, images, PDFs, etc.) to their Stacks and Tasks. Currently, there is no mechanism to associate files with these entities, forcing users to manage reference materials externally.

### 1.2 Proposed Solution

Implement a file attachment system that allows users to attach arbitrary files to Stacks and Tasks. The system will:
- Support offline-first file attachment with background sync
- Store files in Cloudflare R2 (S3-compatible) via presigned URLs
- Generate previews client-side for images and supported document types
- Maintain a complete event trail for all attachment operations
- Provide user-configurable download behavior and storage limits

### 1.3 Goals

- Enable users to attach any file type (up to 50 MB) to Stacks or Tasks
- Support multiple attachments per entity (no hard limit, subject to storage quota)
- Work fully offline with eventual sync
- Provide visual previews where possible (images, PDFs)
- Maintain audit trail through event system
- Give users control over download behavior and storage limits

### 1.4 Non-Goals

- File editing within the app
- File versioning (uploading a new file creates a new attachment)
- Collaborative file editing
- Full-text search of attachment contents
- File conversion (e.g., DOCX to PDF)
- Server-side thumbnail generation

---

## 2. User Stories

### 2.1 Primary User Stories

1. **As a user**, I want to attach a file to a Stack so I can keep reference materials with my project.
2. **As a user**, I want to attach a file to a Task so I can associate deliverables or resources with specific work items.
3. **As a user**, I want to see thumbnails/previews of my attachments so I can quickly identify them.
4. **As a user**, I want to remove an attachment when it's no longer relevant.
5. **As a user**, I want my attachments to sync across all my devices.
6. **As a user**, I want to add attachments while offline and have them sync later.
7. **As a user**, I want to configure whether attachments download automatically or on-demand.
8. **As a user**, I want to see how much storage I'm using and set my own limit.
9. **As a user**, I want to see upload/download progress for large files.

### 2.2 Edge Cases

- User attaches file while offline → sync when online
- User deletes attachment on Device A while offline, views it on Device B → handle gracefully after sync
- User attaches same file to multiple Stacks/Tasks → each is independent attachment
- Large file upload interrupted → resumable upload support

---

## 3. Technical Design

### 3.1 Data Model

#### 3.1.1 Attachment Model (iOS - SwiftData)

```swift
@Model
final class Attachment {
    @Attribute(.unique) var id: String
    var parentId: String              // Stack or Task ID
    var parentType: ParentType        // .stack or .task

    // File metadata
    var filename: String              // Original filename
    var mimeType: String              // e.g., "application/pdf", "image/jpeg"
    var sizeBytes: Int64              // File size in bytes
    var remoteUrl: String?            // R2 URL after upload
    var localPath: String?            // Local file path (for offline/pending uploads)

    // Preview
    var thumbnailData: Data?          // Embedded thumbnail (for images)
    var previewUrl: String?           // Remote preview URL (if generated server-side)

    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var syncState: SyncState          // .pending, .synced, .failed
    var uploadState: UploadState      // .pending, .uploading, .completed, .failed
    var lastSyncedAt: Date?
}
```

#### 3.1.2 Upload State Enum

```swift
enum UploadState: String, Codable {
    case pending      // File selected but upload not started
    case uploading    // Upload in progress
    case completed    // Successfully uploaded to R2
    case failed       // Upload failed (will retry)
}
```

#### 3.1.3 Backend Event Schema

```json
{
  "id": "evt_abc123",
  "type": "attachment.added",
  "ts": "2026-01-02T10:30:00.000Z",
  "device_id": "device_xyz",
  "payload": {
    "attachmentId": "att_123",
    "parentId": "stack_456",
    "parentType": "stack",
    "state": {
      "id": "att_123",
      "parentId": "stack_456",
      "parentType": "stack",
      "filename": "requirements.pdf",
      "mimeType": "application/pdf",
      "sizeBytes": 1048576,
      "url": "https://r2.example.com/attachments/att_123.pdf",
      "createdAt": 1704192600000,
      "updatedAt": 1704192600000,
      "deleted": false
    }
  }
}
```

### 3.2 Event Types

| Event Type | Description | Payload |
|------------|-------------|---------|
| `attachment.added` | File attached to Stack/Task | Full attachment state |
| `attachment.removed` | Attachment removed (soft delete) | attachmentId, parentId, parentType, timestamp |

**Note**: No `attachment.updated` event needed since attachments are immutable (delete + add for replacement).

### 3.3 File Storage Architecture

#### 3.3.1 Upload Flow (Presigned URL Approach)

```
┌─────────────┐     1. Request presigned URL      ┌─────────────┐
│   iOS App   │ ─────────────────────────────────▶│  Go Backend │
│             │ ◀───────────────────────────────── │             │
│             │     2. Return presigned PUT URL   │             │
│             │                                    └─────────────┘
│             │     3. Upload file directly
│             │ ─────────────────────────────────▶ ┌─────────────┐
│             │                                    │ Cloudflare  │
│             │     4. Upload complete (200 OK)   │     R2      │
│             │ ◀───────────────────────────────── └─────────────┘
│             │
│             │     5. Emit attachment.added event
│             │ ─────────────────────────────────▶ Go Backend
└─────────────┘
```

#### 3.3.2 API Endpoints (New)

**POST /apps/{app_id}/attachments/presign**
- Request: `{ filename, mimeType, sizeBytes }`
- Response: `{ uploadUrl, downloadUrl, attachmentId, expiresAt }`
- Generates presigned PUT URL valid for 15 minutes
- Validates: file size ≤ 50 MB, user has available storage quota
- Returns error if quota exceeded

**GET /apps/{app_id}/attachments/{id}/download**
- Returns presigned GET URL for downloading (valid for 1 hour)
- Used for devices that need to download attachment

**GET /apps/{app_id}/users/storage**
- Returns: `{ usedBytes, quotaBytes, attachmentCount }`
- Used to display storage usage in Settings

**PUT /apps/{app_id}/users/settings**
- Request: `{ storageQuotaBytes?, downloadMode? }`
- Allows user to configure storage quota and download preferences

### 3.4 Offline-First Behavior

1. **Attaching a file offline**:
   - File copied to app's Documents directory
   - Attachment record created with `uploadState: .pending`
   - Event created with `syncState: .pending`
   - When online: request presigned URL → upload → emit event
   - Show upload progress bar during upload

2. **Viewing attachments offline**:
   - Default: Download on-demand when user taps to view
   - User-configurable in Settings:
     - **On-demand only** (default): Download when tapped
     - **Auto-download on WiFi**: Download automatically on WiFi, on-demand on cellular
     - **Always auto-download**: Download all attachments immediately
   - Cached locally after first download
   - Show download progress bar while downloading
   - Show placeholder with filename/size if not downloaded

3. **Removing attachment offline**:
   - Mark `isDeleted: true` locally
   - Event created with `syncState: .pending`
   - Sync event when online
   - Local file deleted immediately to free space

### 3.5 User Settings

New settings in the Settings view:

| Setting | Options | Default |
|---------|---------|---------|
| Attachment Download | On-demand / Auto on WiFi / Always | On-demand |
| Storage Quota | 1 GB / 5 GB / 10 GB / Unlimited | 5 GB |

**Storage Usage Display:**
- Show current usage: "2.3 GB of 5 GB used"
- Show attachment count: "47 attachments"
- Warning at 80% capacity
- Block new uploads at 100% with clear error message

### 3.6 Preview Generation (Client-Side Only)

#### 3.6.1 Image Previews
- Generate thumbnail client-side before upload using `CGImage`/`UIImage`
- Store thumbnail as `thumbnailData` (inline Data, ~10-20KB)
- Thumbnail size: 200x200px max dimension, JPEG quality 0.7
- Supported: JPEG, PNG, GIF, HEIC, WebP

#### 3.6.2 PDF/Document Previews
- Use iOS `PDFKit` to render first page as thumbnail
- Use `QLThumbnailGenerator` for Quick Look-supported formats
- Fall back to file type icon if preview unavailable

#### 3.6.3 Other File Types
- Display system file type icon (via `UIDocumentInteractionController` or SF Symbols)
- Show filename and formatted file size (e.g., "2.3 MB")

---

## 4. UI/UX Design

### 4.1 Adding Attachments

**Stack Detail View**:
- Add "Attachments" section below existing content
- "+" button to add new attachment
- Tapping "+" opens system file picker (UIDocumentPickerViewController)
- Support selecting from: Files app, iCloud, Photos

**Task Detail View**:
- Same pattern as Stack

### 4.2 Displaying Attachments

- Grid or list layout of attachments
- Each attachment shows:
  - Thumbnail/preview (if available) or file type icon
  - Filename (truncated with ellipsis if too long)
  - File size (formatted: "2.3 MB")
  - Status indicator:
    - **Pending upload**: Cloud with up arrow + progress bar
    - **Uploading**: Animated progress bar with percentage
    - **Upload failed**: Red exclamation, tap to retry
    - **Not downloaded**: Cloud with down arrow
    - **Downloading**: Progress bar with percentage
    - **Available offline**: Checkmark badge
- Tap to open in Quick Look or share sheet
- Long-press for context menu (Share, Delete, Download/Remove Local Copy)

### 4.3 Removing Attachments

- Swipe to delete, or long-press context menu
- Confirmation dialog: "Remove attachment? This won't delete the file from our servers."

### 4.4 Platform Considerations

**iOS/iPadOS**:
- Use UIDocumentPickerViewController
- Support drag and drop on iPad

**macOS**:
- Use NSOpenPanel
- Support drag and drop from Finder

---

## 5. Backend Changes

### 5.1 New Database Tables

```sql
-- Track uploaded files for quota management and cleanup
CREATE TABLE attachment_files (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    r2_key TEXT NOT NULL,
    filename TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    mime_type TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_referenced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_attachment_files_user ON attachment_files(user_id);
CREATE INDEX idx_attachment_files_cleanup ON attachment_files(last_referenced_at);

-- User settings including attachment preferences
CREATE TABLE user_settings (
    user_id TEXT PRIMARY KEY,
    storage_quota_bytes BIGINT NOT NULL DEFAULT 5368709120,  -- 5 GB
    storage_used_bytes BIGINT NOT NULL DEFAULT 0,
    download_mode TEXT NOT NULL DEFAULT 'on_demand',  -- on_demand, wifi_only, always
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 5.2 R2 Configuration

- Bucket: `dequeue-attachments`
- Region: Automatic (Cloudflare's global network)
- Object naming: `{user_id}/{attachment_id}/{original_filename}`
- CORS configuration for direct iOS uploads:
  ```json
  {
    "AllowedOrigins": ["*"],
    "AllowedMethods": ["GET", "PUT", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }
  ```
- Presigned URL expiry: 15 minutes for upload, 1 hour for download

### 5.3 File Retention Policy

**30-day retention after removal:**
- When attachment is removed, file remains in R2
- `attachment_files.last_referenced_at` updated on each access
- Daily cleanup job deletes files where:
  - No `attachment.added` event references the file AND
  - `last_referenced_at` > 30 days ago
- This allows:
  - Recovery if user re-syncs deleted attachment from another device
  - Grace period for sync propagation across devices

### 5.4 Storage Quota Tracking

- Track per-user storage in `user_settings` table
- Increment on successful upload, decrement on file cleanup
- Enforce quota check before issuing presigned URL
- Default: 5 GB, configurable by user

---

## 6. Decisions Made

| Question | Decision | Rationale |
|----------|----------|-----------|
| Max file size | 50 MB | Handles large PDFs/presentations while keeping uploads manageable |
| Storage quota | 5 GB default, user-configurable | Balance between generous storage and cost control |
| File types | No restrictions | App doesn't execute files; user knows what they need |
| Download behavior | On-demand default, user-configurable | Saves bandwidth; power users can enable auto-download |
| Thumbnails | Client-side only | Simpler architecture, works offline, no server processing |
| Presigned URL duration | 15 min upload, 1 hour download | Short enough for security, long enough for reliability |
| File retention | 30 days after removal | Allows sync propagation and recovery |
| Progress UI | Yes, with progress bar | Essential for large file UX |
| Upload method | Presigned URLs (client → R2 direct) | Less backend load, supports large files better |

---

## 7. Success Metrics

- Users can successfully attach files while offline
- Attachments sync correctly across devices
- Preview generation works for common file types
- No orphaned files accumulate in storage

---

## 8. Implementation Phases

### Phase 1: Backend Infrastructure
**Backend (stacks-sync):**
- Set up R2 bucket and credentials
- Add `attachment_files` and `user_settings` tables (migration)
- Implement presigned URL endpoint (`POST /attachments/presign`)
- Implement download URL endpoint (`GET /attachments/{id}/download`)
- Implement storage/settings endpoints
- Add event type handling for `attachment.added` and `attachment.removed`

**iOS (dequeue-ios):**
- Create `Attachment` SwiftData model
- Create `AttachmentService` with CRUD operations
- Add `attachment.added` and `attachment.removed` to `EventType` enum
- Update `EventService` with attachment event recording
- Update `ProjectorService` to handle attachment events

### Phase 2: Upload/Download Flow
**iOS:**
- Implement presigned URL request flow
- Implement direct R2 upload with progress tracking
- Implement download with progress tracking
- Add retry logic for failed uploads
- Local file caching in Documents directory

### Phase 3: iOS UI
- Add "Attachments" section to `StackDetailView`
- Add "Attachments" section to `TaskDetailView`
- Implement file picker (UIDocumentPickerViewController / NSOpenPanel)
- Implement attachment grid/list display
- Add upload/download progress indicators
- Implement swipe-to-delete and context menu

### Phase 4: Thumbnails & Previews
- Implement image thumbnail generation (CGImage/UIImage)
- Implement PDF first-page thumbnail (PDFKit)
- Implement Quick Look integration for viewing
- Add file type icons for unsupported formats

### Phase 5: Settings & Polish
- Add attachment settings to Settings view
- Implement storage usage display
- Implement download mode configuration
- Implement storage quota configuration
- Add cellular upload warning
- Add quota exceeded handling

### Phase 6: Cleanup & Maintenance
**Backend:**
- Implement daily cleanup job for orphaned files
- Add monitoring for storage usage
- Add metrics for upload/download success rates

---

## 9. Dependencies

- Cloudflare R2 account and credentials
- iOS 17+ (for latest document picker APIs)
- Backend: Go R2/S3 SDK

---

## 10. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Large files consume mobile data | High | 50 MB limit; warn before upload on cellular; on-demand download default |
| R2 costs scale with usage | Medium | 5 GB default quota per user; 30-day cleanup of orphaned files |
| Sync conflicts with attachments | Low | LWW for metadata; files immutable; separate events for add/remove |
| Slow uploads affect UX | Medium | Background upload with progress bar; presigned URLs for direct upload |
| Upload fails mid-transfer | Medium | Local file preserved; automatic retry; resumable uploads if possible |
| Device runs out of storage | Medium | Clear "not downloaded" state; easy way to clear local cache |
| Quota exceeded during offline usage | Low | Block uploads at quota; clear warning message |

---

## Appendix A: File Type Support Matrix

| Category | Extensions | Preview Support |
|----------|------------|-----------------|
| Images | jpg, png, gif, heic, webp | Thumbnail |
| Documents | pdf | First page thumbnail |
| Office | docx, xlsx, pptx | Icon only (or Quick Look) |
| Text | txt, md, json | Icon only |
| Other | * | File type icon |

