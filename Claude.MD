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

---

## Update: Build Production ReaSpeech.luac Files
**Date:** 2025-12-10

### Task
Update deployment packages to include production-ready compiled ReaSpeech files instead of development source files, making them ready to extract and run.

### Problem
Previous packages included the development source structure, requiring users to load `ReaSpeechDev.lua`. This wasn't a production-ready deployment.

### Solution
Build compiled `.luac` bytecode files for both Lua 5.3 and 5.4:

**Build Process:**
1. Install Lua 5.3 and 5.4 compilers
2. Install luacheck for linting
3. Run `make build` in `reascripts/ReaSpeech/`
4. Creates:
   - `build/ReaSpeechBundle.lua` (concatenated source)
   - `build/ReaSpeech-5.3.luac` (compiled for Lua 5.3)
   - `build/ReaSpeech-5.4.luac` (compiled for Lua 5.4)

**Package Structure (Updated):**
```
ReaSpeech.luac              (main script - works with both REAPER 6.x and 7.x)
resources/                  (UI images, etc.)
parakeet-transcribe-*       (platform executable: -windows.exe or -macos)
ffmpeg                      (audio processing: .exe on Windows)
ReaSpeech-Readme.txt        (installation instructions)
```

**User Installation:**
1. Extract package directly to REAPER Scripts directory
   - Windows: `C:\Users\<Name>\AppData\Roaming\REAPER\Scripts\`
   - macOS: `~/Library/Application Support/REAPER/Scripts/`
2. In REAPER Actions, load `ReaSpeech.luac`
3. Ready to use!

**Benefits:**
- ✅ Extract and run - no build required
- ✅ Smaller file size (compiled bytecode)
- ✅ Faster loading in REAPER
- ✅ Production-ready deployment
- ✅ Supports both REAPER 6 and 7

**Windows Build Tools:**
- `choco install lua53` (lua54 package not available)
- Manual build process (PowerShell script)
- Compiles single `ReaSpeech.luac` using Lua 5.3

**macOS Build Tools:**
- `brew install lua@5.4` (lua@5.3 deprecated in Homebrew on 2024-12-14)
- Manual build process (bash script)
- Detects Homebrew path (Apple Silicon vs Intel)
- Compiles single `ReaSpeech.luac` using Lua 5.4

**Build Process Changes:**
- Skipped `make build` to avoid luacheck dependency
- Manual file concatenation matching Makefile logic
- Direct luac compilation without linting
- Single `ReaSpeech.luac` file (works with both REAPER 6.x and 7.x)
- Flat package structure for direct extraction to Scripts directory

### Files Modified
- `.github/workflows/build-executable.yml` - Added build steps and updated package structure

---

## Update: Fix macOS Build After lua@5.3 Deprecation
**Date:** 2025-12-11

### Problem
macOS build started failing with:
```
lua@5.3 has been disabled because it is deprecated upstream! It was disabled on 2024-12-14.
```

Homebrew deprecated the lua@5.3 package, making it unavailable for installation.

### Solution
Changed macOS build to use only Lua 5.4:

**Changes to `.github/workflows/build-executable.yml`:**
- Changed from `brew install lua@5.3 lua@5.4` to only `brew install lua@5.4`
- Updated path detection to find luac5.4 (supports Intel and Apple Silicon Macs)
- Compile bundle with luac5.4 to create single `ReaSpeech.luac`
- Simplified package structure (flat, no version-specific files)

**Backward Compatibility:**
Lua 5.4 bytecode is compatible with Lua 5.3 runtime in most cases. Both REAPER 6.x (Lua 5.3) and REAPER 7.x (Lua 5.4) can run the compiled bytecode.

**Path Detection:**
```bash
if [ -d "/opt/homebrew/opt" ]; then
  LUAC54_PATH="/opt/homebrew/opt/lua@5.4/bin/luac5.4"  # Apple Silicon
else
  LUAC54_PATH="/usr/local/opt/lua@5.4/bin/luac5.4"     # Intel Mac
fi
```

### Files Modified
- `.github/workflows/build-executable.yml` - Updated macOS Lua installation and compilation

---

## Update: Simplify Package Structure
**Date:** 2025-12-11

### Changes
Simplified deployment package structure for easier installation:

**Old Structure:**
```
Scripts/
  ReaSpeech/
    ReaSpeech-5.3.luac
    ReaSpeech-5.4.luac
    resources/
parakeet-transcribe/
  parakeet-transcribe-*
  ffmpeg
```

**New Structure:**
```
ReaSpeech.luac              (single file, works with both REAPER 6.x and 7.x)
resources/
parakeet-transcribe-*       (windows.exe or macos)
ffmpeg                      (.exe on Windows)
ReaSpeech-Readme.txt
```

**Benefits:**
- ✅ Flat structure - extract directly to Scripts directory
- ✅ No nested folders to navigate
- ✅ Single .luac file instead of version-specific files
- ✅ Simpler installation instructions
- ✅ Renamed README.txt to ReaSpeech-Readme.txt for clarity

**Installation:**
Users extract the zip directly to their REAPER Scripts directory and load `ReaSpeech.luac` - that's it!

### Files Modified
- `.github/workflows/build-executable.yml` - Updated package structure for both Windows and macOS
- `Claude.MD` - Updated documentation

---

## Update: Fix macOS Build Path Issues
**Date:** 2025-12-11

### Problem
macOS build failing with two issues:
1. `lua@5.4` package doesn't exist - Homebrew installs as `lua` (version 5.4.8)
2. `cat: source/libs/*/*.lua: No such file or directory` - glob pattern failing because no subdirectories exist in libs/ and main/

### Solution
Updated macOS build script:

**Lua Installation:**
- Changed from `brew install lua@5.4` to `brew install lua`
- Use `which luac` to find compiler in PATH (simpler and more reliable)
- No need for complex path detection for Apple Silicon vs Intel

**File Concatenation:**
- Removed glob patterns for non-existent subdirectories: `source/libs/*/*.lua` and `source/main/*/*.lua`
- Only include actual subdirectory: `source/ui/widgets/*.lua`
- Prevents `cat` from failing on non-matching patterns

**Actual Directory Structure:**
```
source/libs/*.lua           (files only, no subdirectories)
source/ui/*.lua             (files)
source/ui/widgets/*.lua     (subdirectory with files)
source/main/*.lua           (files only, no subdirectories)
```

### Files Modified
- `.github/workflows/build-executable.yml` - Fixed Lua installation and file concatenation
