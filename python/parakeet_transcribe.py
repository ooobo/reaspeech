#!/usr/bin/env python3
"""
parakeet_transcribe.py - Standalone transcription executable for ReaSpeech

This script runs Whisper transcription and outputs JSON segments to stdout.
Progress updates are sent to stderr.
"""

import argparse
import json
import os
import sys
from pathlib import Path

# Add app directory to path to import modules
script_dir = Path(__file__).parent.parent
app_dir = script_dir / "app"
sys.path.insert(0, str(app_dir))

import torch
from faster_whisper import WhisperModel
import whisper


def eprint(*args, **kwargs):
    """Print to stderr for progress/status messages"""
    print(*args, file=sys.stderr, **kwargs)
    sys.stderr.flush()


def load_audio(file_path):
    """Load audio file using whisper's audio loading"""
    eprint(f"Loading audio from {file_path}")
    return whisper.load_audio(file_path)


def transcribe_audio(args):
    """
    Transcribe audio file and output JSON segments to stdout

    Output format (one JSON object per line):
    {"text": "Hello world.", "start": 0.0, "end": 1.5}
    {"text": "How are you?", "start": 1.5, "end": 3.2}
    """

    # Load model
    model_name = args.model or os.getenv("ASR_MODEL", "small")
    model_path = os.getenv("ASR_MODEL_PATH", os.path.join(os.path.expanduser("~"), ".cache", "whisper"))

    eprint(f"Loading model: {model_name}")

    try:
        if torch.cuda.is_available():
            model = WhisperModel(
                model_size_or_path=model_name,
                device="cuda",
                compute_type="float32",
                download_root=model_path
            )
            eprint("Using CUDA acceleration")
        else:
            model = WhisperModel(
                model_size_or_path=model_name,
                device="cpu",
                compute_type="int8",
                download_root=model_path
            )
            eprint("Using CPU")
    except Exception as e:
        eprint(f"ERROR: Failed to load model: {e}")
        sys.exit(1)

    # Load audio
    try:
        audio = load_audio(args.audio_file)
    except Exception as e:
        eprint(f"ERROR: Failed to load audio file: {e}")
        sys.exit(1)

    # Prepare transcription options
    options = {
        "beam_size": 5,
    }

    if args.language:
        options["language"] = args.language

    if args.word_timestamps:
        options["word_timestamps"] = True

    # Transcribe
    eprint("Starting transcription...")

    try:
        segment_generator, info = model.transcribe(audio, **options)

        eprint(f"Detected language: {info.language}")
        eprint(f"Processing segments...")

        segment_count = 0
        for segment in segment_generator:
            # Create segment dictionary
            segment_dict = {
                "text": segment.text,
                "start": segment.start,
                "end": segment.end,
            }

            # Add words if word timestamps are enabled
            if segment.words:
                segment_dict["words"] = [
                    {
                        "word": word.word,
                        "start": word.start,
                        "end": word.end,
                        "probability": word.probability
                    }
                    for word in segment.words
                ]

            # Output JSON to stdout (one line per segment)
            print(json.dumps(segment_dict), flush=True)

            segment_count += 1
            if segment_count % 10 == 0:
                eprint(f"Processed {segment_count} segments...")

        eprint(f"Transcription complete! Total segments: {segment_count}")

    except Exception as e:
        eprint(f"ERROR: Transcription failed: {e}")
        sys.exit(1)


def detect_language(args):
    """
    Detect the language of an audio file

    Output format (JSON to stdout):
    {"language": "en"}
    """

    # Load model
    model_name = os.getenv("ASR_MODEL", "small")
    model_path = os.getenv("ASR_MODEL_PATH", os.path.join(os.path.expanduser("~"), ".cache", "whisper"))

    eprint(f"Loading model: {model_name}")

    try:
        if torch.cuda.is_available():
            model = WhisperModel(
                model_size_or_path=model_name,
                device="cuda",
                compute_type="float32",
                download_root=model_path
            )
        else:
            model = WhisperModel(
                model_size_or_path=model_name,
                device="cpu",
                compute_type="int8",
                download_root=model_path
            )
    except Exception as e:
        eprint(f"ERROR: Failed to load model: {e}")
        sys.exit(1)

    # Load audio
    try:
        audio = load_audio(args.audio_file)
        # Pad or trim to 30 seconds for language detection
        audio = whisper.pad_or_trim(audio)
    except Exception as e:
        eprint(f"ERROR: Failed to load audio file: {e}")
        sys.exit(1)

    # Detect language
    eprint("Detecting language...")

    try:
        segments, info = model.transcribe(audio, beam_size=5)
        detected_lang = info.language

        eprint(f"Detected language: {detected_lang}")

        # Output JSON to stdout
        print(json.dumps({"language": detected_lang}), flush=True)

    except Exception as e:
        eprint(f"ERROR: Language detection failed: {e}")
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description="Transcribe audio files using Whisper"
    )

    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # Transcribe command
    transcribe_parser = subparsers.add_parser("transcribe", help="Transcribe audio file")
    transcribe_parser.add_argument("audio_file", help="Path to audio file")
    transcribe_parser.add_argument("--model", help="Whisper model to use (e.g., tiny, base, small, medium, large)")
    transcribe_parser.add_argument("--language", help="Language code (e.g., en, es, fr)")
    transcribe_parser.add_argument("--word-timestamps", action="store_true", help="Include word-level timestamps")

    # Detect language command
    detect_parser = subparsers.add_parser("detect-language", help="Detect language of audio file")
    detect_parser.add_argument("audio_file", help="Path to audio file")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "transcribe":
        transcribe_audio(args)
    elif args.command == "detect-language":
        detect_language(args)


if __name__ == "__main__":
    main()
