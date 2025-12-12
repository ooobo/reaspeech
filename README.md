# ReaSpeech
![Lint & Test](https://github.com/teamaudio/reaspeech/actions/workflows/check-reascripts.yml/badge.svg)

### Painless speech-to-text transcription inside of REAPER
ReaSpeech is a ReaScript that provides speech-to-text transcription using the Parakeet TDT ASR model. It runs locally on your machine with no cloud services required, building a searchable, project-marker based index of the resulting transcription.

![Screenshot](docs/assets/img/reaspeech-screenshot.png)

# Installation

## Via ReaPack (Recommended)

1. In REAPER, go to **Extensions > ReaPack > Import repositories**
2. Add this repository URL: `https://github.com/ooobo/reaspeech/raw/main/index.xml`
3. Go to **Extensions > ReaPack > Browse packages**
4. Search for "ReaSpeech" and click Install
5. ReaPack will automatically download the correct files for your platform

## Manual Installation

### Windows
1. Download the latest `reaspeech-windows-package.zip` from [GitHub Actions](https://github.com/ooobo/reaspeech/actions) or [Releases](https://github.com/ooobo/reaspeech/releases)
2. Extract to `%AppData%\Roaming\REAPER\Scripts\ReaSpeech`
3. In REAPER: Actions > Show action list > New Action... > Load ReaScript
4. Load `ReaSpeech.lua` from that folder

### macOS
1. Download the latest `reaspeech-macos-package.zip` from [GitHub Actions](https://github.com/ooobo/reaspeech/actions) or [Releases](https://github.com/ooobo/reaspeech/releases)
2. Extract to `~/Library/Application Support/REAPER/Scripts/ReaSpeech`
3. In REAPER: Actions > Show action list > New Action... > Load ReaScript
4. Load `ReaSpeech.lua` from that folder
5. On first run, allow the executables in System Settings > Privacy & Security

# Quick Usage

* Select media items in REAPER
* Run ReaSpeech from the Actions menu
* Choose transcription settings
* Wait for processing (runs locally, no internet required)
* View, edit, and export transcripts

---

# Legacy Docker Installation

For the older Docker-based version, see below:

* Install [Docker](https://www.docker.com/)
* Run the [Docker image](https://hub.docker.com/r/techaudiodoc/reaspeech)
* Navigate to [localhost:9000](http://localhost:9000/)

## Docker Commands

### CPU

    docker run -d -p 9000:9000 --name reaspeech techaudiodoc/reaspeech:latest

### GPU: Windows/NVIDIA

    docker run -d --gpus all -p 9000:9000 --name reaspeech-gpu techaudiodoc/reaspeech:latest-gpu

### GPU: Apple Silicon

Please see our [Apple Silicon GPU instructions](docs/no-docker.md#apple-silicon-gpu)

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
