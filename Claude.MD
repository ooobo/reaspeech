# ReaSpeech Local Executable Backend - Development Notes

## Project Overview

Converting ReaSpeech from Docker/Flask/HTTP backend to local Python executable using Parakeet TDT ASR model.

## Current Status

### ✅ Completed
- ✅ Created `parakeet_transcribe.py` using onnx-asr (from reaspeech-lite)
- ✅ Modified `ReaSpeechAPI.lua` for local executable execution
- ✅ Simplified `ReaSpeechWorker.lua` (removed HTTP polling)
- ✅ Updated UI components (ASRControls, ASRPlugin, WhisperModels)
- ✅ Fixed all Lua lint warnings
- ✅ Fixed unit tests (TestReaSpeechUI)
- ✅ Added GitHub Actions workflow to build Windows executable
- ✅ Fixed ffmpeg integration (using ffmpeg-python library)
- ✅ Transcription working with minimal overhead (<1s on 10min files)
- ✅ Completion marker file for reliable detection
- ✅ Integrated timing logs with existing logging infrastructure
- ✅ Cleaned up all experimental code

### ✅ Performance Optimized

**Final measurements**:
- Direct execution: 10min file = **49s**
- Through REAPER: 10min file = **~49-50s** (<1s overhead)

**Solution**: Completion marker file approach
- Python writes segments to stdout (simple print)
- Python writes completion marker file as final step
- Lua polls for marker file existence (fast check)
- Shell redirection captures stdout/stderr
- Progress based on jobs completed

**STATUS**: ✅ READY TO MERGE

## Architecture

### File Flow
```
REAPER → ReaSpeechAPI:transcribe()
       → ExecProcess directly
       → cmd /c "parakeet-transcribe.exe file.wav --completion-marker marker.tmp > stdout.tmp 2> stderr.tmp"
       → ReaSpeechWorker polls marker file every 1.0s
       → When marker exists: read stdout once, parse segments
       → Return to callback → Create transcript UI
```

**Key features**:
- Direct ExecProcess (no wrapper overhead)
- Completion marker file (faster than size checks)
- Python flushes stdout before writing marker
- Lua uses existing Logging() infrastructure
- Progress based on jobs completed (no file reads during processing)

### Key Files

**Python**:
- `python/parakeet_transcribe.py` - Main transcription script
  - Arguments: audio_file, --model, --chunk-duration, --quantization, --completion-marker
  - Outputs: segments to stdout (JSON per line)
  - Timing: `[TIMING] Python processing time: X.XXs` to stderr
- `python/parakeet_transcribe.spec` - PyInstaller spec

**Lua**:
- `reascripts/ReaSpeech/source/main/ReaSpeechAPI.lua` - API wrapper
  - Creates inline process object with ready/error/result/progress methods
  - Uses Logging() for timing output
- `reascripts/ReaSpeech/source/main/ReaSpeechWorker.lua` - Job management
  - Polls process:ready() every 1s
  - Calculates progress based on completed/total jobs
- `reascripts/ReaSpeech/source/ui/ASRPlugin.lua` - UI callback handler

**CI/CD**:
- `.github/workflows/build-executable.yml` - Builds Windows .exe

## Technical Details

### Completion Detection
**Current approach** (in `ReaSpeechAPI.lua:ready()`):
1. Every 1.0s (via ReaSpeechWorker), check if marker file exists
2. If marker exists: Process complete (Python writes marker as final step)
3. Read stdout file once for all segments
4. Read stderr file once for error checking
5. Clean up all temp files

**Why marker file**:
- Checking file existence is faster than opening/seeking large files
- Marker is tiny (5 bytes) vs potentially large stdout
- Written as absolute last step after stdout.flush()
- No race conditions or partial reads

### Progress Calculation
Progress is based on **jobs completed**, not file reads:
```lua
completed_jobs = total_jobs - pending_jobs - 1 (active)
active_job_progress = 0.5 (50% while processing)
progress = (completed_jobs + active_job_progress) / total_jobs
```

This avoids all file I/O overhead during processing.

### Logging
**Python**: Simple print statements to stderr
```python
print(f"[TIMING] Python processing time: {elapsed:.2f}s", file=sys.stderr)
```

**Lua**: Uses existing Logging() infrastructure
```lua
self.logger:log(string.format("[TIMING] Lua wall-clock time: %.2fs", elapsed))
```

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
- Sample rate: 16kHz (ffmpeg converts automatically)
- Channels: Mono (ffmpeg converts automatically)
- Formats: Any format ffmpeg supports (WAV, MP3, FLAC, etc.)

### Chunking
- Files > 120s: Chunked with 15s overlap
- Chunks processed sequentially
- Progress shows as 50% during active job processing

## Performance Summary

### What We Learned
1. **Direct file writes are slow**: --output-file added 20s overhead
2. **Progress file polling is slow**: Even at 30s intervals added overhead
3. **Shell redirection is fast**: Faster than direct Python file writes
4. **Completion marker is fastest**: File existence check is faster than size check
5. **Minimal polling is key**: Only check marker file, no reads during processing

### Final Implementation
- Python: stdout + marker file
- Lua: ExecProcess + marker polling
- Overhead: <1s on 10min files
- Clean: All experimental code removed

## Known Limitations

1. **No cancellation**: Can't kill running process mid-transcription
2. **No real-time progress**: Progress shows 50% during processing (based on jobs, not chunks)
3. **No detect_language**: Placeholder implementation only (returns "en")

## Environment

- OS: Windows (primary), Linux/Mac (untested with executable)
- REAPER version: Any with ReaImGui support
- Python: 3.11 (for building executable)
- Branch: `claude/local-executable-backend-01Mf5tLZS3tnEc1bUGrqbHdU`
