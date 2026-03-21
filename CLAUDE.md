# ReaSpeech Local Executable Backend - Development Notes

## Project Overview

ReaSpeech uses a local Rust executable (parakeet-rs) for Parakeet TDT ASR transcription.

## Current Status

### ✅ Completed
- ✅ Rust-based transcription using parakeet-rs 0.2.6 from crates.io
- ✅ Modified `ReaSpeechAPI.lua` for local executable execution
- ✅ Simplified `ReaSpeechWorker.lua` (removed HTTP polling)
- ✅ Updated UI components (ASRControls, ASRPlugin, Models)
- ✅ GitHub Actions workflow builds Windows and macOS executables
- ✅ Completion marker file for reliable detection
- ✅ Both v2 and v3 Parakeet models supported (dynamic vocab_size)
- ✅ Int8 quantization support (smaller, faster models)

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
- Rust flushes stdout before writing marker
- Progress based on jobs completed (no file reads during processing)

### Key Files

**Rust** (separate repo: `ooobo/parakeet-transcribe`):
- Transcription CLI built with parakeet-rs 0.2.6 from crates.io
- Arguments: audio_file, --model, --chunk-duration, --quantization, --completion-marker
- Outputs: segments to stdout (JSON per line)
- Pre-built binaries downloaded by release workflow

**Lua**:
- `reascripts/ReaSpeech/source/main/ReaSpeechAPI.lua` - API wrapper
- `reascripts/ReaSpeech/source/main/ReaSpeechWorker.lua` - Job management
- `reascripts/ReaSpeech/source/ui/ASRPlugin.lua` - UI callback handler

**CI/CD**:
- `.github/workflows/release.yml` - Bundles Lua, downloads binaries from `ooobo/parakeet-transcribe`, creates GitHub releases
- `.github/workflows/check-reascripts.yml` - Lints and tests Lua code

## Configuration

### Model
- Default: `nemo-parakeet-tdt-0.6b-v2` (English-only, smaller vocab)
- Alternative: `nemo-parakeet-tdt-0.6b-v3` (multilingual, larger vocab)
- Downloaded automatically from HuggingFace on first run
- Cached in `~/Library/Caches/parakeet-tdt/` (macOS) or equivalent

### Quantization
- Default: `int8` (smaller, ~652MB models)
- Alternative: `none` (fp32, larger ~2.5GB models)

### Audio Requirements
- Sample rate: 16kHz (converted automatically via rubato)
- Channels: Mono (converted automatically)
- Formats: WAV, MP3, FLAC, AAC/M4A, OGG/Vorbis, ALAC, ADPCM (via symphonia)

### Chunking
- Files > 120s: Chunked with 15s overlap
- Chunks processed sequentially
- Progress shows as 50% during active job processing

## Known Limitations

1. **No cancellation**: Can't kill running process mid-transcription
2. **No real-time progress**: Progress shows 50% during processing (based on jobs, not chunks)
3. **No detect_language**: Placeholder implementation only (returns "en")

## Environment

- OS: Windows, macOS (both supported)
- REAPER version: Any with ReaImGui support
