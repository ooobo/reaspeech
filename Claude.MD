# ReaSpeech Development Progress

## Current Session: Fix Transcript Export and Insert Bugs
**Branch:** `claude/interface-updates-01VgcaEUa6rNUVcNg5Yoad5W`
**Date:** 2025-12-09

### Context
This branch already had the clickable "insert file" functionality implemented, but had two critical bugs that needed fixing:

1. Export failing when media items deleted from timeline
2. Insert failing when file not on timeline

### Tasks

#### 1. Fix Export Bug ✅
**Problem:** Export fails when media files have been deleted from timeline
```
bad argument #1 to 'getter_f' (MediaItem expected)
```
**Location:** ReaUtil.lua:55, called from TranscriptSegment.lua:313-314
**Solution:** Validate item/take pointers before calling ReaUtil functions

#### 2. Fix Insert Bug ✅
**Problem:** Insert fails when file doesn't exist on timeline
```
bad argument #1 to 'GetMediaItemTake_Source' (MediaItem_Take expected)
```
**Location:** TranscriptUI.lua:464
**Solution:** Store source path during init, validate take before use, fallback to stored path

### Implementation Complete

#### Changes Made

**1. TranscriptSegment.lua**
- ✅ Fixed `to_table()` to validate items before calling ReaUtil (lines 314-319)
  - Uses `reaper.ValidatePtr2()` to check if item/take still valid
  - Only exports GUID if pointer is valid
- ✅ Updated `init()` to store full source path in `_source_path` (line 31)
- ✅ Added `get_source_path()` method (lines 225-236)
  - Validates take before accessing
  - Returns empty string if take invalid
  - Wrapped in Trap for safety

**2. TranscriptUI.lua**
- ✅ Fixed `insert_media_at_cursor()` to handle deleted items (lines 460-476)
  - Calls `segment:get_source_path()` which validates take
  - Falls back to stored `_source_path` if take invalid
  - Validates file exists before attempting insertion
  - Proper error messages for missing files

### Bug Fixes Summary
- ✅ Export now works even when media items deleted from timeline
- ✅ Insert functionality works even when original file not on timeline
- ✅ Proper pointer validation using `reaper.ValidatePtr2()`
- ✅ Graceful error handling with console messages

### Files Modified
- `reascripts/ReaSpeech/source/main/TranscriptSegment.lua` - Export fixes + source path storage
- `reascripts/ReaSpeech/source/ui/TranscriptUI.lua` - Insert fixes with validation

---

## Update: Add macOS Build to GitHub Workflow
**Date:** 2025-12-10

### Task
Add macOS executable build to GitHub Actions workflow alongside existing Windows build.

### Implementation
Added `build-macos` job to `.github/workflows/build-executable.yml`:
- **Runner:** `macos-latest`
- **FFmpeg:** Installed via Homebrew
- **Python:** 3.11 (same as Windows build)
- **Output:** `parakeet-transcribe-macos` executable
- **Testing:** Includes `--help` validation and executable permissions
- **Artifact:** Uploaded with 90-day retention

### Key Differences from Windows Build
- Uses `brew install ffmpeg` instead of `choco`
- Uses bash scripts instead of PowerShell
- Executable has no `.exe` extension
- Requires `chmod +x` before testing

### Files Modified
- `.github/workflows/build-executable.yml` - Added macOS build job

---

## Update: Add Deployment Packages
**Date:** 2025-12-10

### Task
Create complete deployment packages bundling ReaSpeech Lua scripts, parakeet-transcribe executable, and FFmpeg for easy installation.

### Implementation
Enhanced both Windows and macOS build jobs to create deployment packages:

**Package Contents:**
- `ReaSpeech/` - Complete Lua script installation (excluding tests/build artifacts)
- `parakeet-transcribe/` - Transcription engine folder containing:
  - Platform-specific parakeet-transcribe executable
  - FFmpeg binary for audio processing
- `README.txt` - Installation and usage instructions

**Windows Package:**
- Downloads FFmpeg from https://www.gyan.dev/ffmpeg/builds/
- Uses PowerShell for packaging
- Creates `reaspeech-windows-package.zip`
- Installation path: `C:\Users\<Name>\AppData\Roaming\REAPER\Scripts\`

**macOS Package:**
- Downloads FFmpeg from https://evermeet.cx/ffmpeg/
- Uses rsync and zip for packaging
- Creates `reaspeech-macos-package.zip`
- Installation path: `~/Library/Application Support/REAPER/Scripts/`
- Includes quarantine removal instructions for macOS Gatekeeper

**Artifacts Available:**
1. Individual executables (for developers):
   - `parakeet-transcribe-windows` (Windows .exe)
   - `parakeet-transcribe-macos` (macOS binary)
2. Complete packages (for users):
   - `reaspeech-windows-package` (zip)
   - `reaspeech-macos-package` (zip)

All artifacts retained for 90 days.

### Files Modified
- `.github/workflows/build-executable.yml` - Added FFmpeg download and package creation steps

---

## Update: Add FFmpeg Caching
**Date:** 2025-12-10

### Task
Add GitHub Actions caching for FFmpeg to avoid re-downloading on every build, improving build times while maintaining the simple bundled package approach.

### Implementation
Added `actions/cache@v4` to both Windows and macOS workflows:

**Windows Caching:**
- Cache key: `ffmpeg-windows-essentials-v1`
- Cache path: `ffmpeg-cache-windows`
- Only downloads if cache miss
- Subsequent builds use cached FFmpeg (~50MB)

**macOS Caching:**
- Cache key: `ffmpeg-macos-7.1-v1`
- Cache path: `ffmpeg-cache-macos`
- Only downloads if cache miss
- Subsequent builds use cached FFmpeg (~50MB)

**How It Works:**
1. Check cache for FFmpeg
2. If cache hit: Copy from cache (fast)
3. If cache miss: Download, extract, and cache for next run
4. Copy to dist folder for packaging

**Benefits:**
- ✅ First build: Downloads FFmpeg (~2-3 minutes)
- ✅ Subsequent builds: Uses cache (~5 seconds)
- ✅ Users still get complete packages with FFmpeg bundled
- ✅ No runtime downloads needed
- ✅ Cache invalidation via version key bump

**Cache Invalidation:**
To update FFmpeg version, increment cache key:
- Windows: `ffmpeg-windows-essentials-v2`
- macOS: `ffmpeg-macos-7.2-v1` (update version in key)

### Files Modified
- `.github/workflows/build-executable.yml` - Added FFmpeg caching steps
