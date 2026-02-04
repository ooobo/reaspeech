use clap::Parser;
use eyre::{Context, Result};
use hf_hub::api::sync::Api;
use parakeet_rs::{ParakeetTDT, TimestampMode, Transcriber};
use rubato::{FftFixedIn, Resampler};
use serde::Serialize;
use std::fs::{self, File};
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};
use std::time::Instant;
use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::DecoderOptions;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

mod mpeg_wav_reader;

const SAMPLE_RATE: u32 = 16000;
const OVERLAP_DURATION: f32 = 15.0;

#[derive(Parser, Debug)]
#[command(name = "parakeet-transcribe")]
#[command(about = "Transcribe audio using Parakeet TDT")]
struct Args {
    /// Path to audio file
    audio_file: String,

    /// Model name (v2 or v3)
    #[arg(long, default_value = "nemo-parakeet-tdt-0.6b-v2")]
    model: String,

    /// Chunk duration in seconds for long files
    #[arg(long, default_value = "120.0")]
    chunk_duration: f32,

    /// Model quantization (int8 or none)
    #[arg(long, default_value = "int8")]
    quantization: String,

    /// File to create when transcription is complete
    #[arg(long)]
    completion_marker: Option<String>,
}

#[derive(Serialize, Debug)]
struct Segment {
    text: String,
    start: f32,
    end: f32,
}

/// Get the HuggingFace repo ID for a model name
fn get_repo_id(model: &str) -> Result<&'static str> {
    match model {
        "nemo-parakeet-tdt-0.6b-v2" => Ok("istupakov/parakeet-tdt-0.6b-v2-onnx"),
        "nemo-parakeet-tdt-0.6b-v3" => Ok("istupakov/parakeet-tdt-0.6b-v3-onnx"),
        _ => Err(eyre::eyre!(
            "Unknown model: {}. Supported: nemo-parakeet-tdt-0.6b-v2, nemo-parakeet-tdt-0.6b-v3",
            model
        )),
    }
}

/// Get model directory for a specific model/quantization combo
fn get_model_dir(model: &str, quantization: &str) -> Result<PathBuf> {
    let cache_dir = dirs::cache_dir()
        .ok_or_else(|| eyre::eyre!("Could not find cache directory"))?
        .join("parakeet-tdt")
        .join(format!("{model}-{quantization}"));
    Ok(cache_dir)
}

/// Download model files using hf-hub and set up the model directory
fn ensure_model_files(model: &str, quantization: &str) -> Result<PathBuf> {
    let repo_id = get_repo_id(model)?;
    let model_dir = get_model_dir(model, quantization)?;
    fs::create_dir_all(&model_dir)?;

    let use_int8 = quantization.to_lowercase() == "int8";

    // Check if model files already exist
    let encoder_path = model_dir.join("encoder-model.onnx");
    let decoder_path = model_dir.join("decoder_joint-model.onnx");
    let vocab_path = model_dir.join("vocab.txt");

    if encoder_path.exists() && decoder_path.exists() && vocab_path.exists() {
        eprintln!("Using cached model files from {model_dir:?}");
        return Ok(model_dir);
    }

    eprintln!("Downloading model files from {repo_id}...");
    let api = Api::new().wrap_err("Failed to create HuggingFace API client")?;
    let repo = api.model(repo_id.to_string());

    // Download vocab.txt (same for all quantizations)
    eprintln!("  Downloading vocab.txt...");
    let vocab_src = repo
        .get("vocab.txt")
        .wrap_err("Failed to download vocab.txt")?;
    fs::copy(&vocab_src, &vocab_path).wrap_err("Failed to copy vocab.txt")?;

    if use_int8 {
        // Int8 quantized models (smaller, no .data file needed)
        eprintln!("  Downloading encoder-model.int8.onnx...");
        let encoder_src = repo
            .get("encoder-model.int8.onnx")
            .wrap_err("Failed to download encoder-model.int8.onnx")?;
        fs::copy(&encoder_src, &encoder_path).wrap_err("Failed to copy encoder model")?;

        eprintln!("  Downloading decoder_joint-model.int8.onnx...");
        let decoder_src = repo
            .get("decoder_joint-model.int8.onnx")
            .wrap_err("Failed to download decoder_joint-model.int8.onnx")?;
        fs::copy(&decoder_src, &decoder_path).wrap_err("Failed to copy decoder model")?;
    } else {
        // FP32 models (larger, need .data file for encoder)
        eprintln!("  Downloading encoder-model.onnx...");
        let encoder_src = repo
            .get("encoder-model.onnx")
            .wrap_err("Failed to download encoder-model.onnx")?;
        fs::copy(&encoder_src, &encoder_path).wrap_err("Failed to copy encoder model")?;

        eprintln!("  Downloading encoder-model.onnx.data...");
        let encoder_data_src = repo
            .get("encoder-model.onnx.data")
            .wrap_err("Failed to download encoder-model.onnx.data")?;
        let encoder_data_path = model_dir.join("encoder-model.onnx.data");
        fs::copy(&encoder_data_src, &encoder_data_path)
            .wrap_err("Failed to copy encoder model data")?;

        eprintln!("  Downloading decoder_joint-model.onnx...");
        let decoder_src = repo
            .get("decoder_joint-model.onnx")
            .wrap_err("Failed to download decoder_joint-model.onnx")?;
        fs::copy(&decoder_src, &decoder_path).wrap_err("Failed to copy decoder model")?;
    }

    eprintln!("Model files downloaded to {model_dir:?}");
    Ok(model_dir)
}

/// Load audio from any supported format and convert to 16kHz mono f32 samples
/// Supports: WAV, BWF, MP3, FLAC, OGG, AAC/M4A, and more via symphonia
fn load_audio_native(path: &Path) -> Result<Vec<f32>> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("unknown");

    // Check for MPEG-in-WAV (common in BWF files)
    // BWF files can contain MPEG-encoded audio which needs special handling
    if ext.eq_ignore_ascii_case("wav") || ext.eq_ignore_ascii_case("bwf") {
        let mut file = File::open(path).wrap_err("Failed to open audio file")?;
        if let Some(mpeg_data) = mpeg_wav_reader::extract_mpeg_from_wav(&mut file)? {
            eprintln!("Detected MPEG audio in WAV container, extracting...");
            // Process the extracted MPEG data
            let cursor = Cursor::new(mpeg_data);
            let mss = MediaSourceStream::new(Box::new(cursor), Default::default());

            let mut hint = Hint::new();
            hint.with_extension("mp3");

            return load_audio_from_stream(mss, hint, ext);
        }
    }

    let file = File::open(path).wrap_err("Failed to open audio file")?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    // Provide a hint about the file extension
    // Treat BWF as WAV for format detection
    let mut hint = Hint::new();
    let hint_ext = if ext.eq_ignore_ascii_case("bwf") {
        "wav"
    } else {
        ext
    };
    hint.with_extension(hint_ext);

    load_audio_from_stream(mss, hint, ext)
}

/// Load audio from a media source stream
fn load_audio_from_stream(
    mss: MediaSourceStream,
    hint: Hint,
    original_ext: &str,
) -> Result<Vec<f32>> {
    let unsupported_msg = format!(
        "Cannot decode .{} files. Supported: WAV, BWF, MP3, FLAC, AAC/M4A, OGG. \
        In REAPER, select the item and use 'Glue items' (Cmd+Shift+G) to convert it first.",
        original_ext
    );
    let probed = symphonia::default::get_probe()
        .format(
            &hint,
            mss,
            &FormatOptions::default(),
            &MetadataOptions::default(),
        )
        .map_err(|_| eyre::eyre!("{unsupported_msg}"))?;

    let mut format = probed.format;

    // Find the first audio track
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or_else(|| eyre::eyre!("No audio track found"))?;

    let track_id = track.id;
    let codec_params = track.codec_params.clone();

    let source_sample_rate = codec_params
        .sample_rate
        .ok_or_else(|| eyre::eyre!("Unknown sample rate"))?;
    let channels = codec_params.channels.map_or(1, |c| c.count());

    // Create decoder
    let mut decoder = symphonia::default::get_codecs()
        .make(&codec_params, &DecoderOptions::default())
        .map_err(|_| eyre::eyre!("{unsupported_msg}"))?;

    // Decode all samples
    let mut all_samples: Vec<f32> = Vec::new();

    loop {
        let packet = match format.next_packet() {
            Ok(packet) => packet,
            Err(symphonia::core::errors::Error::IoError(e))
                if e.kind() == std::io::ErrorKind::UnexpectedEof =>
            {
                break;
            }
            Err(e) => return Err(e).wrap_err("Failed to read packet"),
        };

        if packet.track_id() != track_id {
            continue;
        }

        let decoded = match decoder.decode(&packet) {
            Ok(decoded) => decoded,
            Err(symphonia::core::errors::Error::DecodeError(_)) => continue,
            Err(e) => return Err(e).wrap_err("Failed to decode packet"),
        };

        // Convert to f32 samples
        let spec = *decoded.spec();
        let num_frames = decoded.frames();

        if num_frames == 0 {
            continue;
        }

        let mut sample_buf = SampleBuffer::<f32>::new(num_frames as u64, spec);
        sample_buf.copy_interleaved_ref(decoded);

        all_samples.extend(sample_buf.samples());
    }

    if all_samples.is_empty() {
        return Err(eyre::eyre!("No audio samples decoded"));
    }

    // Convert to mono if multi-channel
    let mono_samples = if channels > 1 {
        all_samples
            .chunks(channels)
            .map(|chunk| chunk.iter().sum::<f32>() / channels as f32)
            .collect()
    } else {
        all_samples
    };

    // Resample to 16kHz if needed
    let final_samples = if source_sample_rate != SAMPLE_RATE {
        resample_audio(&mono_samples, source_sample_rate, SAMPLE_RATE)?
    } else {
        mono_samples
    };

    Ok(final_samples)
}

/// Resample audio from source_rate to target_rate using high-quality FFT resampling
fn resample_audio(samples: &[f32], source_rate: u32, target_rate: u32) -> Result<Vec<f32>> {
    if source_rate == target_rate {
        return Ok(samples.to_vec());
    }

    // Calculate resampling parameters
    let chunk_size = 4096;
    let mut resampler = FftFixedIn::<f32>::new(
        source_rate as usize,
        target_rate as usize,
        chunk_size,
        2, // sub-chunks for better quality
        1, // mono
    )
    .wrap_err("Failed to create resampler")?;

    let mut output = Vec::new();
    let mut pos = 0;

    // Process in chunks
    while pos < samples.len() {
        let end = (pos + chunk_size).min(samples.len());
        let mut chunk = samples[pos..end].to_vec();

        // Pad last chunk if needed
        if chunk.len() < chunk_size {
            chunk.resize(chunk_size, 0.0);
        }

        let resampled = resampler
            .process(&[chunk], None)
            .wrap_err("Resampling failed")?;

        if !resampled.is_empty() {
            output.extend(&resampled[0]);
        }

        pos += chunk_size;
    }

    // Trim to expected length (avoid padding artifacts at the end)
    let expected_len = (samples.len() as f64 * target_rate as f64 / source_rate as f64) as usize;
    output.truncate(expected_len);

    Ok(output)
}

/// Clean up text output from TDT model
/// - Collapse repeated digits (fixes decoder looping issue)
/// - Remove spurious periods before numbers (but keep space)
/// - Fix spacing around punctuation
fn clean_text(text: &str) -> String {
    let mut result = String::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;

    while i < chars.len() {
        let c = chars[i];

        // Handle " ." or " ," sequences
        if c == ' ' && i + 1 < chars.len() {
            let next = chars[i + 1];
            // " .com" -> ".com" (space before period followed by letter)
            if next == '.' && i + 2 < chars.len() && chars[i + 2].is_alphabetic() {
                i += 1; // Skip the space, keep the period
                continue;
            }
            // " .123" -> " 123" (space before period followed by digit - keep space, skip period)
            if next == '.' && i + 2 < chars.len() && chars[i + 2].is_ascii_digit() {
                result.push(' ');
                i += 2; // Skip space and period, continue to digit
                continue;
            }
        }

        // Skip standalone period before digit: ".123" -> "123"
        if (c == '.' || c == ',') && i + 1 < chars.len() && chars[i + 1].is_ascii_digit() {
            // Only skip if at start or after space
            if result.is_empty() || result.ends_with(' ') {
                i += 1;
                continue;
            }
        }

        result.push(c);

        // If this is a digit, collapse repeated identical digits (keep max 3)
        if c.is_ascii_digit() {
            let mut repeat_count = 1;
            while i + 1 < chars.len() && chars[i + 1] == c && repeat_count < 3 {
                i += 1;
                result.push(chars[i]);
                repeat_count += 1;
            }
            // Skip any remaining identical digits
            while i + 1 < chars.len() && chars[i + 1] == c {
                i += 1;
            }
        }

        i += 1;
    }
    result.trim().to_string()
}

/// Check if a segment should be filtered out (empty or just punctuation)
fn is_valid_segment(text: &str) -> bool {
    let trimmed = text.trim();
    !trimmed.is_empty() && trimmed.chars().any(|c| c.is_alphanumeric())
}

fn transcribe_with_chunking(
    parakeet: &mut ParakeetTDT,
    audio_samples: Vec<f32>,
    chunk_duration: f32,
) -> Result<Vec<Segment>> {
    let duration = audio_samples.len() as f32 / SAMPLE_RATE as f32;

    if duration <= chunk_duration {
        // Short file - process in one go
        let result = parakeet.transcribe_samples(
            audio_samples,
            SAMPLE_RATE,
            1,
            Some(TimestampMode::Sentences),
        )?;

        return Ok(result
            .tokens
            .into_iter()
            .map(|t| Segment {
                text: clean_text(&t.text),
                start: t.start,
                end: t.end,
            })
            .filter(|s| is_valid_segment(&s.text))
            .collect());
    }

    // Long file - process in chunks
    let chunk_samples = (chunk_duration * SAMPLE_RATE as f32) as usize;
    let overlap_samples = (OVERLAP_DURATION * SAMPLE_RATE as f32) as usize;
    let stride = chunk_samples - overlap_samples;

    let mut all_segments: Vec<Segment> = Vec::new();
    let total_samples = audio_samples.len();

    let mut start = 0;
    let mut chunk_idx = 0;

    while start < total_samples {
        let end = (start + chunk_samples).min(total_samples);
        let chunk: Vec<f32> = audio_samples[start..end].to_vec();
        let chunk_start_time = start as f32 / SAMPLE_RATE as f32;

        eprintln!(
            "Processing chunk {} ({:.1}s - {:.1}s)...",
            chunk_idx + 1,
            chunk_start_time,
            end as f32 / SAMPLE_RATE as f32
        );

        let result =
            parakeet.transcribe_samples(chunk, SAMPLE_RATE, 1, Some(TimestampMode::Sentences))?;

        for token in result.tokens {
            let adjusted_start = token.start + chunk_start_time;
            let adjusted_end = token.end + chunk_start_time;

            // Skip segments in overlap region that were already captured
            if chunk_idx > 0 {
                let overlap_end = chunk_start_time + OVERLAP_DURATION;
                if adjusted_start < overlap_end {
                    // Check if this overlaps with existing segments
                    if let Some(last) = all_segments.last() {
                        if adjusted_start < last.end {
                            continue;
                        }
                    }
                }
            }

            let cleaned_text = clean_text(&token.text);
            if is_valid_segment(&cleaned_text) {
                all_segments.push(Segment {
                    text: cleaned_text,
                    start: adjusted_start,
                    end: adjusted_end,
                });
            }
        }

        chunk_idx += 1;
        start += stride;

        if end >= total_samples {
            break;
        }
    }

    Ok(all_segments)
}

fn run(args: &Args) -> Result<()> {
    let start_time = Instant::now();

    // Check input file exists
    let audio_path = Path::new(&args.audio_file);
    if !audio_path.exists() {
        return Err(eyre::eyre!("Audio file not found: {}", args.audio_file));
    }

    // Validate quantization
    let quantization = args.quantization.to_lowercase();
    if quantization != "int8" && quantization != "none" {
        return Err(eyre::eyre!(
            "Invalid quantization '{}'. Use 'int8' or 'none'",
            args.quantization
        ));
    }

    // Ensure model files are downloaded
    eprintln!(
        "Using model: {} with quantization: {}",
        args.model, quantization
    );
    let model_dir = ensure_model_files(&args.model, &quantization)
        .wrap_err("Failed to download model files")?;

    // Load and convert audio to 16kHz mono (native, no ffmpeg needed)
    eprintln!("Loading audio...");
    let audio_samples = load_audio_native(audio_path)?;
    let duration = audio_samples.len() as f32 / SAMPLE_RATE as f32;
    eprintln!(
        "Loaded {:.1}s of audio ({} samples)",
        duration,
        audio_samples.len()
    );

    // Load model
    eprintln!("Loading model...");
    let mut parakeet = ParakeetTDT::from_pretrained(&model_dir, None)
        .wrap_err("Failed to load Parakeet TDT model")?;

    // Transcribe with chunking
    eprintln!("Transcribing...");
    let segments = transcribe_with_chunking(&mut parakeet, audio_samples, args.chunk_duration)?;

    // Output segments as JSON lines to stdout
    for segment in &segments {
        println!("{}", serde_json::to_string(segment)?);
    }

    // Flush stdout before writing marker
    std::io::stdout().flush()?;

    let elapsed = start_time.elapsed();
    eprintln!("Rust processing time: {:.2}s", elapsed.as_secs_f32());

    Ok(())
}

fn main() {
    let args = Args::parse();
    let marker_path = args.completion_marker.clone();

    let result = run(&args);

    // Always write completion marker if specified (even on error)
    if let Some(ref path) = marker_path {
        let _ = fs::write(path, "done\n");
    }

    // Handle errors with user-friendly output
    if let Err(e) = result {
        eprintln!("ERROR: {:#}", e);
        std::process::exit(1);
    }
}
