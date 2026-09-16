"""Mac / server helper for vocal separation with Demucs.

Runs on your Mac (or any server with Python + torch), NOT on the iPhone.
The iOS app uploads audio to POST /separate and downloads the vocals WAV.

Setup (Mac):
    python3 -m venv .venv && source .venv/bin/activate
    pip install fastapi uvicorn demucs torch torchaudio soundfile

Run:
    uvicorn demucs_server:app --host 0.0.0.0 --port 8000

Then in the iOS app: Settings -> Vocal isolation -> Mac / Server helper
and enter http://<your-mac-ip>:8000

License note: Demucs is MIT-licensed (Meta). Separated vocals are derived
from the user's own audio and stay between their devices — the helper does
not redistribute lyrics or audio.
"""
from __future__ import annotations

import shutil
import subprocess
import uuid
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.responses import FileResponse

WORKDIR = Path("/tmp/lyricfinder-demucs")
WORKDIR.mkdir(parents=True, exist_ok=True)

app = FlaskLikeApp = FastAPI(title="LyricFinder Demucs Helper")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/separate")
async def separate(file: UploadFile = File(...)) -> dict:
    job = WORKDIR / uuid.uuid4().hex
    job.mkdir(parents=True, exist_ok=True)
    src = job / (file.filename or "input.m4a")
    try:
        with src.open("wb") as f:
            shutil.copyfileobj(file.file, f)
    finally:
        await file.close()

    # Demucs CLI: python -m demucs --two-stems vocals -o <job> <src>
    cmd = ["python3", "-m", "demucs", "--two-stems", "vocals", "-o", str(job), str(src)]
    try:
        subprocess.run(cmd, check=True, capture_output=True, timeout=1800)
    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Demucs failed: {e.stderr.decode()[-2000:]}")

    # Demucs output layout: <job>/htdemucs/<name>/vocals.wav
    candidates = sorted(job.rglob("vocals.wav"))
    if not candidates:
        raise HTTPException(status_code=500, detail="Demucs produced no vocals.wav")
    vocals = candidates[0]
    public_name = f"{uuid.uuid4().hex}_vocals.wav"
    dest = WORKDIR / public_name
    shutil.copy(vocals, dest)
    return {"vocals_url": f"/downloads/{public_name}"}


@app.get("/downloads/{name}")
def download(name: str):
    path = WORKDIR / name
    if not path.is_file():
        raise HTTPException(status_code=404, detail="Not found")
    return FileResponse(path, media_type="audio/wav", filename=name)
