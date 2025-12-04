#!/usr/bin/env python3
"""
ReaSpeech Parakeet TDT Transcription Service
Standalone executable for ASR transcription using onnx-asr
"""
import sys
import os
import time

# Handle multiprocessing spawn on macOS
if '-c' in sys.argv:
    code_index = sys.argv.index('-c') + 1
    if code_index < len(sys.argv):
        exec(sys.argv[code_index])
    sys.exit(0)

import argparse
import json
from pathlib import Path
import numpy as np
import ffmpeg

os.environ['HF_HUB_DISABLE_PROGRESS_BARS'] = '1'
os.environ['HF_HUB_DISABLE_TELEMETRY'] = '1'

from onnx_asr import load_model

SAMPLE_RATE = 16000
FFMPEG_BIN = os.getenv("FFMPEG_BIN", "ffmpeg")

def tokens_to_sentences(tokens, timestamps):
    """
    Group tokens into sentences based on punctuation.

    Args:
        tokens: List of token strings
        timestamps: List of timestamps (one per token, representing token start time)

    Returns:
        List of dicts with {text, start, end}
    """
    if not tokens or not timestamps:
        return []

    sentences = []
    current_tokens = []
    current_start = timestamps[0] if timestamps else 0.0
    sentence_end_puncts = {'.', '!', '?'}

    for i, (token, ts) in enumerate(zip(tokens, timestamps)):
        current_tokens.append(token)
        is_sentence_end = any(token.strip().endswith(p) for p in sentence_end_puncts)
        is_last_token = (i == len(tokens) - 1)

        if is_sentence_end or is_last_token:
            if i + 1 < len(timestamps):
                current_end = timestamps[i + 1]
            else:
                current_end = ts + 0.16

            text = ''.join(current_tokens).strip()
            if text:
                sentences.append({
                    'text': text,
                    'start': current_start,
                    'end': current_end
                })

            current_tokens = []
            if i + 1 < len(timestamps):
                current_start = timestamps[i + 1]

    return sentences

def load_audio_with_ffmpeg(audio_path, sr=SAMPLE_RATE):
    """
    Load audio using ffmpeg-python library (handles ANY audio format).
    Returns audio as float32 numpy array at specified sample rate (default 16kHz mono).

    This approach works with WAV, MP3, BWF, FLAC, etc. - anything ffmpeg supports.
    Based on the original ReaSpeech backend implementation.
    """
    try:
        # Use ffmpeg-python to decode audio while down-mixing and resampling
        # This launches ffmpeg subprocess internally
        out, _ = (
            ffmpeg.input(audio_path, threads=0)
            .output("-", format="s16le", acodec="pcm_s16le", ac=1, ar=sr)
            .run(cmd=FFMPEG_BIN, capture_stdout=True, capture_stderr=True)
        )
    except ffmpeg.Error as e:
        raise RuntimeError(f"Failed to load audio: {e.stderr.decode()}") from e

    # Convert bytes to numpy array
    return np.frombuffer(out, np.int16).flatten().astype(np.float32) / 32768.0


def transcribe_with_chunking(asr, audio_path, chunk_duration=120.0, overlap_duration=15.0):
    """
    Transcribe audio file with chunking for long files, preserving timestamps.

    Args:
        asr: ASR model instance (default: Parakeet TDT 0.6b v3 int8)
        audio_path: Path to audio file (any format ffmpeg supports)
        chunk_duration: Duration of each chunk in seconds
        overlap_duration: Overlap between chunks in seconds

    Returns:
        List of sentence dicts with {text, start, end}
    """

    # Load entire audio file with ffmpeg (supports all formats)
    audio = load_audio_with_ffmpeg(audio_path, sr=SAMPLE_RATE)

    duration = len(audio) / SAMPLE_RATE

    if duration <= chunk_duration:
        # Short file - process in one go
        result = asr.recognize(audio, sample_rate=SAMPLE_RATE)
        if hasattr(result, 'tokens') and hasattr(result, 'timestamps'):
            return tokens_to_sentences(result.tokens, result.timestamps)
        else:
            text = result.text if hasattr(result, 'text') else str(result)
            return [{'text': text, 'start': 0.0, 'end': duration}]

    # Long file - process in chunks
    all_tokens = []
    all_timestamps = []

    chunk_samples = int(chunk_duration * SAMPLE_RATE)
    overlap_samples = int(overlap_duration * SAMPLE_RATE)
    stride = chunk_samples - overlap_samples

    total_samples = len(audio)

    chunk_idx = 0
    for start in range(0, total_samples, stride):
        end = min(start + chunk_samples, total_samples)
        chunk = audio[start:end]

        chunk_start = start / SAMPLE_RATE

        result = asr.recognize(chunk, sample_rate=SAMPLE_RATE)

        if hasattr(result, 'tokens') and hasattr(result, 'timestamps'):
            adjusted_timestamps = [ts + chunk_start for ts in result.timestamps]

            if chunk_idx > 0 and all_timestamps:
                last_prev_time = all_timestamps[-1]
                overlap_end = chunk_start + overlap_duration

                filtered_tokens = []
                filtered_timestamps = []
                for token, ts in zip(result.tokens, adjusted_timestamps):
                    if ts >= overlap_end or ts > last_prev_time:
                        filtered_tokens.append(token)
                        filtered_timestamps.append(ts)

                all_tokens.extend(filtered_tokens)
                all_timestamps.extend(filtered_timestamps)
            else:
                all_tokens.extend(result.tokens)
                all_timestamps.extend(adjusted_timestamps)

        chunk_idx += 1
        if end >= total_samples:
            break

    # Convert tokens to sentences and return
    return tokens_to_sentences(all_tokens, all_timestamps)

def main():
    parser = argparse.ArgumentParser(description='Transcribe audio using Parakeet TDT')
    parser.add_argument('audio_file', type=str, help='Path to audio file')
    parser.add_argument('--model', type=str, default='nemo-parakeet-tdt-0.6b-v2',
                       help='Model name (default: nemo-parakeet-tdt-0.6b-v2)')
    parser.add_argument('--chunk-duration', type=float, default=120.0,
                       help='Chunk duration in seconds for long files (default: 120.0)')
    parser.add_argument('--quantization', type=str, default='int8',
                       help='Model quantization (default: int8, options: int8, None)')
    parser.add_argument('--completion-marker', type=str, default=None,
                       help='File to create when transcription is complete')
    args = parser.parse_args()

    audio_file = Path(args.audio_file)
    if not audio_file.exists():
        print(f"ERROR: Audio file not found: {audio_file}", file=sys.stderr)
        sys.exit(1)

    try:
        start_time = time.time()

        quantization = None if args.quantization.lower() == 'none' else args.quantization
        asr = load_model(args.model, quantization=quantization).with_timestamps()
        sentences = transcribe_with_chunking(asr, str(audio_file), chunk_duration=args.chunk_duration)

        # Write all segments to stdout
        for segment in sentences:
            print(json.dumps(segment))

        # Ensure all stdout is flushed before writing marker
        sys.stdout.flush()

        elapsed = time.time() - start_time
        print(f"Python processing time: {elapsed:.2f}s", file=sys.stderr)

        # Write completion marker file if specified
        if args.completion_marker:
            with open(args.completion_marker, 'w') as f:
                f.write('done\n')

    except Exception as e:
        print(f"ERROR: Transcription failed: {str(e)}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
