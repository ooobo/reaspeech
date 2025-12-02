# ReaSpeech Local Executable Backend - Development Notes

## Project Overview

Converting ReaSpeech from Docker/Flask/HTTP backend to local Python executable using Parakeet TDT ASR model.

## Current Status

### ✅ Completed
- ✅ Created `parakeet_transcribe.py` using onnx-asr (from reaspeech-lite)
- ✅ Created `ProcessExecutor.lua` to replace `CurlRequest.lua`
- ✅ Modified `ReaSpeechAPI.lua` for local executable execution
- ✅ Simplified `ReaSpeechWorker.lua` (removed HTTP polling)
- ✅ Updated UI components (ASRControls, ASRPlugin, WhisperModels)
- ✅ Fixed all Lua lint warnings
- ✅ Fixed unit tests (TestReaSpeechUI)
- ✅ Added GitHub Actions workflow to build Windows executable
- ✅ Fixed ffmpeg integration (using ffmpeg-python library)
- ✅ Basic transcription working (segments received, transcript created)
- ✅ Removed verbose debug logging
- ✅ Completion detection working (checks stdout file size > 0)

### ⚠️ Current Issue: PERFORMANCE SLOWDOWN - NOW FIXED!

**Problem**: Transcription through REAPER was ~2.5x slower than running executable directly

**Measurements**:
- Direct execution: 10min file = **49s**
- Through REAPER (old): 10min file = **~120-150s**
- Through REAPER (new): **EXPECTED ~49s** (needs testing)

**Root Cause Identified**: `cmd /c` shell wrapper + file redirection overhead on Windows
- Windows shell redirection is slow
- `cmd /c` adds extra process overhead
- File buffering behavior unpredictable with stdout/stderr redirection

**Solution Implemented**: Direct file output instead of shell redirection
1. ✅ Added `--output-file` and `--progress-file` arguments to Python script
2. ✅ Python writes directly to files (no shell redirection)
3. ✅ Eliminated `cmd /c` wrapper - executable runs directly
4. ✅ Explicit flush control in Python for reliable completion detection
5. ✅ Updated ProcessExecutor to use new file arguments

**STATUS**: ⚠️ NEEDS TESTING - Executable must be rebuilt for changes to take effect

## Architecture

### File Flow
```
REAPER → ReaSpeechAPI:transcribe()
       → ProcessExecutor:execute_async()
       → parakeet-transcribe-windows.exe file.wav --output-file out.json --progress-file prog.txt
       → ProcessExecutor polls output file size every 1.0s
       → When output size > 0: read all segments at once
       → Return to callback → Create transcript UI
```

**Key improvement**: No more `cmd /c` wrapper or shell redirection!

### Key Files

**Python**:
- `python/parakeet_transcribe.py` - Main transcription script
- `python/parakeet_transcribe.spec` - PyInstaller spec

**Lua**:
- `reascripts/ReaSpeech/source/libs/ProcessExecutor.lua` - Async process execution
- `reascripts/ReaSpeech/source/main/ReaSpeechAPI.lua` - API wrapper
- `reascripts/ReaSpeech/source/main/ReaSpeechWorker.lua` - Job management
- `reascripts/ReaSpeech/source/ui/ASRPlugin.lua` - UI callback handler

**CI/CD**:
- `.github/workflows/build-executable.yml` - Builds Windows .exe

## Technical Details

### Completion Detection
**Current approach** (in `ProcessExecutor.lua:62-105`):
1. Every 1.0s, check output file size (seek to end, get position, close)
2. If `output size > 0`: Process complete (Python only writes when done)
3. Read output file once for all segments
4. Read progress file once for error checking

**Key improvements**:
- Python writes directly to files (no shell redirection overhead)
- Explicit flush ensures data is written immediately
- No file locking contention with direct file I/O

### Performance Investigation Notes

**What we learned**:
- Short files (< 120s, no chunking): No slowdown (never had the problem)
- Long files (6+ chunks): Progressive slowdown (now FIXED)
- Root cause: `cmd /c` + shell redirection overhead on Windows
- Solution: Direct file I/O eliminates overhead

**What we tried**:
1. ~~Flushing stdout~~ - Made it worse (more I/O overhead with redirection)
2. ~~File locking contention~~ - Minimized but not enough
3. ~~Polling frequency~~ - Optimized to 1.0s but still slow
4. ✅ **Direct file output** - Eliminates shell overhead entirely!

**Performance gains expected**:
- Eliminates `cmd /c` process creation overhead
- Removes shell redirection overhead
- Direct file writes with explicit flush control
- Should match native command-line performance (~49s for 10min file)

## Building the Executable

### Local Build
```bash
cd python
pip install pyinstaller onnx-asr onnxruntime ffmpeg-python numpy huggingface-hub
pyinstaller parakeet_transcribe.spec
# Output: python/dist/parakeet-transcribe-windows.exe
```

### GitHub Actions
Push to `claude/local-executable-backend-*` branch triggers build.
Download artifact from Actions tab (90 day retention).

### Dependencies
**Python packages** (bundled in .exe):
- onnx-asr
- onnxruntime
- ffmpeg-python
- numpy
- huggingface-hub

**External dependencies** (user must install):
- FFmpeg binary (can be in PATH or same dir as .exe)

## Configuration

### Model
- Default: `nemo-parakeet-tdt-0.6b-v2`
- Downloaded automatically from HuggingFace on first run
- Cached in user's HuggingFace cache directory

### Audio Requirements
- Sample rate: 16kHz
- Channels: Mono
- Formats: Any (ffmpeg handles conversion)

### Chunking
- Files > 120s: Chunked with 15s overlap
- Chunks processed sequentially
- Progress based on chunk X/Y (not currently working due to no stderr reads)

## Git Branch

Branch: `claude/local-executable-backend-016aTjzw6rKKUHZcNzxhwtig`

**Recent commits**:
1. `7c7e2ae` - Remove flush=True to eliminate synchronous file I/O
2. `c932f4d` - Fix premature completion detection using stdout presence
3. `972e98e` - Eliminate file I/O during processing to avoid contention
4. `6b83a18` - Reduce I/O contention by polling less frequently
5. `097afea` - Fix file locking contention causing progressive slowdown

## Next Steps

1. **URGENT**: Test if performance improved with flush=True removal
   - User reported it's "longer now" so something went wrong
   - May need to revert or try different approach

2. If still slow, investigate:
   - Profile Python execution
   - Check Windows file system overhead
   - Try different completion detection method
   - Consider alternative IPC methods (pipes, sockets)

3. Once performance fixed:
   - Re-enable progress bar based on chunks (currently stuck at 50%)
   - Add better error handling
   - Update documentation
   - Create PR to main branch

## Known Issues

1. **Performance**: 2.5x slowdown on long files (primary issue)
2. **Progress bar**: Stuck at 50% during processing (no stderr reads)
3. **No cancellation**: Can't kill running process
4. **No detect_language**: Placeholder implementation only

## Questions for User

- What's the actual processing time now with flush=True removed?
- Does direct execution (CMD) still take 49s for 10min file?
- Are you using the rebuilt executable or old one?
- Any antivirus software that might be scanning temp files?

## Environment

- OS: Windows (user testing)
- REAPER version: Unknown
- Python: 3.11 (for building executable)
- Branch: `claude/local-executable-backend-016aTjzw6rKKUHZcNzxhwtig`
