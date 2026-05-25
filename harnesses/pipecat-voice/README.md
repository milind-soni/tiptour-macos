# TipTour Pipecat Voice Sidecar

Local voice sidecar for TipTour. TipTour stays the macOS perception/action engine; this process owns voice orchestration and calls TipTour through the localhost harness.

## Run

```bash
cd harnesses/pipecat-voice
brew install portaudio
uv venv --python 3.12
uv pip install -e '.[pipecat]'
uv run uvicorn server:app --host 127.0.0.1 --port 7860
```

When TipTour starts the sidecar from the settings UI or voice hotkey, it sends the saved Gemini key to the localhost-only sidecar. For standalone curl tests, set `GOOGLE_API_KEY` or `GEMINI_API_KEY`.

## Endpoints

- `GET /v1/health`
- `POST /v1/start`
- `POST /v1/stop`
- `GET /v1/events`
- `GET /v1/tools`
- `POST /v1/tools/{tool_name}`

Tool calls proxy to TipTour at `http://127.0.0.1:19474` and Hermes at `http://127.0.0.1:8642`.
