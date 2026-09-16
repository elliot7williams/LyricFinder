# LyricFinder — Offline iOS Lyrics Transcriber (SwiftUI)

Free, local-first song-lyrics transcription: **Import Audio → Play → Transcribe (offline) → Karaoke lyrics → Edit → Export TXT/LRC/SRT/VTT**.

No OpenAI API key required. No per-song costs.

## 1. Open the project

- Requires **Xcode 16+, iOS 17+**.
- Open `LyricFinder/LyricFinder.xcodeproj` (generated — all Swift files are already referenced).
- Select an iPhone simulator or device, press **Run**.
- The app compiles with **zero third-party dependencies** (preview transcription engine included so the full pipeline works immediately).

## 2. Enable real on-device transcription (recommended)

Add **WhisperKit** (Argmax, MPL-2.0 — permissive, commercial App Store distribution allowed, actively maintained, Core ML optimized for Apple Silicon):

1. In Xcode: **File → Add Package Dependencies…**
2. Enter: `https://github.com/argmaxinc/WhisperKit`
3. Add to the `LyricFinder` target.
4. Rebuild — `WhisperTranscriptionManager.swift` detects `canImport(WhisperKit)` automatically and switches from the preview engine to real transcription. No other code changes needed.

Why WhisperKit over alternatives:
- **whisper.cpp** (MIT, also App Store compatible) works but needs manual model + audio-converter wiring; a `whisper.cpp` SPM package (`ggerganov/whisper.cpp`) can be swapped in behind the same `TranscriptionEngine` protocol.
- **OpenAI API** is deliberately *not* required (paid, online-only). Keep it as an optional future engine behind the same protocol if you want a cloud fallback.

Model guide (Settings → Default model):
| Model | Size | iPhone fit |
|---|---|---|
| Tiny | ~75 MB | fastest, drafts |
| Base | ~145 MB | fast |
| Small | ~465 MB | **recommended balance** |
| Turbo | ~1.6 GB | fast, near-large accuracy |
| Medium/Large | 1.5–2.9 GB | best accuracy, may need newer devices |

Only one model is held in memory at a time; switching models releases the previous one.

## 3. Vocal isolation

| Mode | What happens |
|---|---|
| **Off** | Transcribe the original mix (default, works everywhere). |
| **On-device (experimental)** | Passthrough today; reserved slot in `VocalSeparationManager.swift` for a future Core ML separator (e.g. converted Hybrid-Demucs/MDX). Full Demucs is too heavy for direct iPhone execution. |
| **Mac / Server helper** | Uploads to `ServerHelper/demucs_server.py` (Demucs, MIT) on your Mac, downloads vocals-only WAV for cleaner transcription. |

To use the helper: `pip install fastapi uvicorn demucs torch torchaudio soundfile`, run `uvicorn demucs_server:app --port 8000`, enter the Mac's LAN URL in Settings.

## 4. Project structure

```
LyricFinder/LyricFinder/
  LyricFinderApp.swift
  Models/      LyricLine, TranscriptionProject, WhisperModelType
  Managers/    AudioImportManager, AudioPlayerManager, VocalSeparationManager,
               WhisperTranscriptionManager, ProjectManager, ExportManager
  Parsing/     LyricsParser, LyricsSyncManager
  Views/       MainTabView, LibraryView, TranscribeView, NowPlayingView,
               SettingsView, LyricsEditorView, Components/{WaveformView, LyricRowView}
  Utilities/   Extensions
ServerHelper/  demucs_server.py (Demucs helper, runs on Mac/server)
```

Clean boundaries: each manager owns one concern, `async/await` throughout, heavy work off the main thread, transcription cancellable, lyrics are plain `Codable` structs so TXT/LRC/SRT/VTT export and future features (translation, verse/chorus labels, confidence scores) slot in without refactors.

## 5. MVP flow (works today)

Import Audio → Play Audio → Run Local Transcription → Timestamped Lyrics → Edit Lyrics → Export TXT/LRC/SRT → Save to Library → Karaoke Now Playing (tap line = seek, word highlight when word timings exist).

LRC output uses `[mm:ss.xx]` tags compatible with standard music players.

## 6. Licenses (App Store suitability, verified)

- **App code here**: yours to use commercially.
- **WhisperKit**: MPL-2.0 — allows commercial App Store use (disclose/source-offer obligations apply to the WhisperKit files themselves, not your app code).
- **whisper.cpp / ggml**: MIT — commercial use allowed.
- **Demucs** (server helper only): MIT — commercial use allowed.
- **Whisper model weights**: MIT (OpenAI) — commercial use allowed.
- No Apple Music stream ripping: the app only transcribes user-imported files; no lyric-redistribution database is included (users transcribe their own audio — important for copyright).

## 7. Future expansion hooks

- `TranscriptionEngine` protocol: add cloud/mic/live engines.
- `VocalSeparator` protocol: plug in a Core ML `.mlpackage` separator.
- `LyricLine.confidence` + `words`: confidence UI, model comparison.
- `TranscriptionProject.language`: language detection + translation.
- Section labeling (Verse/Chorus/Bridge) can be derived from `lyrics` timestamps in a new `StructureAnalyzer` without touching existing managers.
