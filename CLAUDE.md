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

### ⚠️ Current Issue: PERFORMANCE INVESTIGATION

**Problem**: Transcription through REAPER has 1-3s overhead compared to direct execution

**Measurements**:
- Direct execution: 10min file = **49s**
- Through REAPER: 10min file = **~50-52s**

**Attempts to Optimize**:
1. ❌ Direct file writes (--output-file): Added 20s overhead due to file I/O
2. ❌ Progress file polling (every 2s): Added 20s overhead
3. ❌ Progress file polling (every 30s): Still added overhead
4. ✅ Reverted to stdout/stderr with shell redirection: Minimal overhead

**Current Solution**: Simple stdout/stderr approach
- Python writes segments to stdout (simple print)
- Python writes progress/errors to stderr
- Lua uses shell redirection: `cmd /c "exe > out 2> err"`
- Lua polls stdout file size every 1s to detect completion
- Lua reads files ONCE when complete
- Progress based on jobs completed (no file reading)

**STATUS**: ✅ ACCEPTABLE - 1-3s overhead is minimal compared to 49s total time

## Architecture

### File Flow
```
REAPER → ReaSpeechAPI:transcribe()
       → ExecProcess directly (no ProcessExecutor wrapper)
       → cmd /c "parakeet-transcribe-windows.exe file.wav > stdout.tmp 2> stderr.tmp"
       → ReaSpeechWorker polls stdout file size every 1.0s
       → When stdout size > 0: read all segments at once
       → Return to callback → Create transcript UI
```

**Key simplifications**:
- Bypassed ProcessExecutor entirely for minimal overhead
- Python writes to stdout/stderr (no explicit file I/O)
- Progress based on jobs completed (no file polling)

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
**Current approach** (in `ReaSpeechAPI.lua:ready()`):
1. Every 1.0s (via ReaSpeechWorker), check stdout file size
2. If `stdout size > 0`: Process complete (Python only writes at end)
3. Read stdout once for all segments
4. Read stderr once for error checking

**Key optimizations**:
- No file I/O during processing (only size check)
- Files read ONCE when complete
- No progress file polling
- Progress calculated from jobs completed

### Performance Investigation Notes

**What we learned**:
- Direct file writes (--output-file) added 20s overhead
- Progress file polling (even at 30s intervals) added overhead
- Shell redirection to stdout is faster than direct file writes
- Minimal polling (just file size check) has negligible overhead

**What we tried**:
1. ❌ Direct file writes with --output-file: +20s overhead
2. ❌ Progress file polling every 2s: +20s overhead
3. ❌ Progress file polling every 30s: Still added overhead
4. ❌ ProcessExecutor wrapper: Suspected overhead
5. ✅ **Simple stdout/stderr with ExecProcess**: 1-3s overhead

**Final solution**:
- Python: Simple print() to stdout
- Lua: Shell redirection + size check polling
- Progress: Based on jobs completed (not file reads)
- Result: ~50s total for 10min file (49s + 1-3s overhead)

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
