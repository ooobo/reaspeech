# ReaSpeech Fork

### Painless speech-to-text transcription inside of REAPER

This is a fork of [ReaSpeech](https://github.com/TeamAudio/reaspeech). Main differences are docker-based transcription service was replaced with a standalone executable based on [parakeet-rs](https://github.com/altunenes/parakeet-rs) (built from [ooobo/parakeet-transcribe](https://github.com/ooobo/parakeet-transcribe)), a few improvements to the transcript display, and simple insertion of the raw audio.

The main aim of the fork is to target running the transcription on regular hardware without CPU. Parakeet TDT v2 is state of the art for English ASR in speed/accuracy, in most tests without a GPU transcribed 1 hour of audio in about 3-5mins.

# Installation

## Via ReaPack (Recommended)

1. In REAPER, go to **Actions > ReaPack: Import repositories**
2. Add this repository URL: `https://github.com/ooobo/reaspeech/raw/beta/index.xml`
3. Go to **Actions > ReaPack: Browse packages**
4. Search for "ReaSpeech" and click Install
5. ReaPack will automatically download the correct files for your platform.

To update, run **Actions > ReaPack: Synchronize packages**

## Manual Installation

### Windows

1. Download the latest `reaspeech-windows-package.zip` from [Releases](https://github.com/ooobo/reaspeech/releases)
2. Extract to `%AppData%\Roaming\REAPER\Scripts\ReaSpeech`
3. In REAPER: Actions > Show action list > New Action... > Load ReaScript
4. Load `ReaSpeech.lua` from that folder

### macOS

1. Download the latest `reaspeech-macos-package.zip` from [Releases](https://github.com/ooobo/reaspeech/releases)
2. Extract to `~/Library/Application Support/REAPER/Scripts/ReaSpeech`
3. In REAPER: Actions > Show action list > New Action... > Load ReaScript
4. Load `ReaSpeech.lua` from that folder
5. On first run, you may need to allow the executables in System Settings > Privacy & Security

# Quick Usage

- Select media items in REAPER
- Run ReaSpeech from the Actions menu
- Choose transcription settings
- Wait for processing (runs locally, no internet required)
- View, edit, and export transcripts

# Note

Docker and native python support has been replaced so will no longer work.

# Credits

As per original credits:

## ReaSpeech Team

- [Dave Benjamin](https://github.com/ramen)
- [Jason Nanna](https://github.com/smrl)
- [Kyle Vande Slunt](https://github.com/kvande-standingwave)
- [Michael DeFreitas](https://github.com/mikeylove)
- [Roel Sanchez](https://github.com/roelsan)

## Third-Party Software

Transcription is provided by the [parakeet-rs](https://github.com/altunenes/parakeet-rs) library.

ReaSpeech uses [ReaImGui](https://github.com/cfillion/reaimgui) by Christian Fillion for its user interface toolkit.

# Licensing

ReaSpeech is licensed under the terms of the
[GPLv3](https://www.gnu.org/licenses/gpl-3.0.en.html).
All source files in this repository should be
considered GPL-licensed unless otherwise specified.
