# ReaSpeech
![Lint & Test](https://github.com/teamaudio/reaspeech/actions/workflows/check-reascripts.yml/badge.svg)

### Painless speech-to-text transcription inside of REAPER
ReaSpeech is a ReaScript frontend that will take your project's media items and run them through Whisper for speech-to-text transcription, building a searchable, project-marker based index of the resulting transcription.

![Screenshot](docs/assets/img/reaspeech-screenshot.png)

# Quick Usage

## Local Executable Backend (Recommended)

This version uses a local Python script instead of Docker, making it simpler and faster to set up.

### Requirements

* Python 3.8 or higher
* ReaImGui (REAPER extension)
* Whisper model dependencies (installed automatically on first run)

### Installation

1. Install ReaImGui from [ReaPack](https://reapack.com/)
2. Install Python dependencies:
   ```bash
   pip install torch whisper faster-whisper
   ```
3. Copy the ReaSpeech folder to your REAPER Scripts directory
4. Run the ReaSpeech script from REAPER

The first time you run a transcription, Whisper will download the selected model (this may take a few minutes).

### GPU Acceleration

For faster transcription with NVIDIA GPUs, install the CUDA-enabled version of PyTorch:
```bash
pip install torch --index-url https://download.pytorch.org/whl/cu118
```

For Apple Silicon Macs, the Metal Performance Shaders (MPS) backend is used automatically.

## Docker Backend (Legacy)

The Docker backend is still available but is no longer the recommended approach. See [Docker Usage](docs/docker.md) for details.

### CPU

    docker run -d -p 9000:9000 --name reaspeech techaudiodoc/reaspeech:latest

### GPU: Windows/NVIDIA

    docker run -d --gpus all -p 9000:9000 --name reaspeech-gpu techaudiodoc/reaspeech:latest-gpu

---

For more detailed instructions, see [Docker Usage](docs/docker.md)

# Documentation

* [Docker Usage](docs/docker.md)
* [Running Outside of Docker](docs/no-docker.md)
* [Contributing](docs/CONTRIBUTING.md)
* [Development](docs/development.md)

# Credits

## ReaSpeech Team

* [Dave Benjamin](https://github.com/ramen)
* [Jason Nanna](https://github.com/smrl)
* [Kyle Vande Slunt](https://github.com/kvande-standingwave)
* [Michael DeFreitas](https://github.com/mikeylove)
* [Roel Sanchez](https://github.com/roelsan)

## Third-Party Software

ReaSpeech's initial web service and Docker setup were based on the [Whisper ASR Webservice](https://github.com/ahmetoner/whisper-asr-webservice) project.

Transcription is provided by the [Faster Whisper](https://github.com/SYSTRAN/faster-whisper) library.

ReaSpeech uses [ReaImGui](https://github.com/cfillion/reaimgui) by Christian Fillion for its user interface toolkit.

# Licensing

ReaSpeech is licensed under the terms of the
[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html).
Portions are derived from the
[whisper-asr-webservice](https://github.com/ahmetoner/whisper-asr-webservice)
project, which is MIT-licensed. All source files in this repository should be
considered GPL-licensed unless otherwise specified.
