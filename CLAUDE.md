# ReaSpeech Local Executable Backend - Development Notes

## Project Overview

ReaSpeech uses a local Rust executable (parakeet-rs) for Parakeet TDT ASR transcription.

## Current Status

### ✅ Completed
- ✅ Rust-based transcription using parakeet-rs (fork with v2 model support)
- ✅ Modified `ReaSpeechAPI.lua` for local executable execution
- ✅ Simplified `ReaSpeechWorker.lua` (removed HTTP polling)
- ✅ Updated UI components (ASRControls, ASRPlugin, WhisperModels)
- ✅ GitHub Actions workflow builds Windows and macOS executables
- ✅ Completion marker file for reliable detection
- ✅ Both v2 and v3 Parakeet models supported
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

**Rust** (`rust-parakeet/`):
- `src/main.rs` - Main transcription CLI
  - Arguments: audio_file, --model, --chunk-duration, --quantization, --completion-marker
  - Outputs: segments to stdout (JSON per line)
  - Timing: `Rust processing time: X.XXs` to stderr
- `Cargo.toml` - Two binary targets: parakeet-transcribe-macos, parakeet-transcribe-windows
- `parakeet-rs-fork/` - Patched parakeet-rs with dynamic vocab_size (fixes v2 model support)

**Lua**:
- `reascripts/ReaSpeech/source/main/ReaSpeechAPI.lua` - API wrapper
- `reascripts/ReaSpeech/source/main/ReaSpeechWorker.lua` - Job management
- `reascripts/ReaSpeech/source/ui/ASRPlugin.lua` - UI callback handler

**CI/CD**:
- `.github/workflows/build-executable.yml` - Builds Windows/macOS executables
- `.github/workflows/release.yml` - Creates GitHub releases

## Building the Executable

### Local Build (macOS)
```bash
cd rust-parakeet
~/.cargo/bin/cargo build --release --bin parakeet-transcribe-macos
# Output: rust-parakeet/target/release/parakeet-transcribe-macos
```

### Local Build (Windows)
```bash
cd rust-parakeet
cargo build --release --bin parakeet-transcribe-windows
# Output: rust-parakeet/target/release/parakeet-transcribe-windows.exe
```

### GitHub Actions
Push to `main` or `claude/**` branches triggers build.
Download artifacts from Actions tab (90 day retention).

### Dependencies
**Rust crates** (compiled into binary):
- parakeet-rs (local fork)
- clap, serde, serde_json
- symphonia (native audio decoding: WAV, MP3, FLAC, AAC, OGG, etc.)
- rubato (high-quality audio resampling)
- hf-hub (HuggingFace model download)
- eyre, dirs

**External dependencies**: None (fully self-contained executable)

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

## parakeet-rs Fork

The fork at `rust-parakeet/parakeet-rs-fork/` patches the original parakeet-rs to support both v2 and v3 models.

**Key change** (`src/model_tdt.rs`):
- Original: `vocab_size: 8193` (hardcoded for v3)
- Patched: Reads vocab_size from `vocab.txt` at runtime

This allows v2 (1025 tokens) and v3 (8193 tokens) to work with the same code.

## Known Limitations

1. **No cancellation**: Can't kill running process mid-transcription
2. **No real-time progress**: Progress shows 50% during processing (based on jobs, not chunks)
3. **No detect_language**: Placeholder implementation only (returns "en")

## Environment

- OS: Windows, macOS (both supported)
- REAPER version: Any with ReaImGui support
- Rust: stable toolchain (for building)
