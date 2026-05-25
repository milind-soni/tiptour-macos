# Pipecat Voice Harness

Pipecat should run as a local sidecar next to TipTour, not inside the macOS app.

TipTour keeps ownership of:

- menu bar UI
- cursor overlay and pointer animation
- local perception and target IDs
- screen capture privacy controls
- CUA desktop actions
- one-action workflow safety rails

Pipecat owns:

- realtime voice transport
- turn detection
- STT / LLM / TTS pipeline selection
- short spoken progress updates
- tool calls into TipTour and optional delegation to Hermes

## Local Services

| Service | URL | Role |
| --- | --- | --- |
| TipTour harness | `http://127.0.0.1:19474` | Local perception, grounding, actions, skills, action history |
| Hermes Agent | `http://127.0.0.1:8642` | Optional long-horizon planner |
| Pipecat sidecar | `http://127.0.0.1:7860` | Realtime voice runtime |

The first Pipecat sidecar should expose:

- `GET /v1/health`
- `POST /v1/start`
- `POST /v1/stop`
- `GET /v1/events`
- `GET /v1/tools`
- `POST /v1/tools/{tool_name}`

The Pipecat sidecar may use SmallWebRTC or WebSocket during local development. For production, prefer WebRTC/Daily-style transport and keep provider API keys server-side.
When the Pipecat Voice connection is enabled in TipTour, the existing voice hotkey starts/stops this sidecar session instead of opening the built-in Gemini Live session.

The current local sidecar lives at `harnesses/pipecat-voice`:

```bash
cd harnesses/pipecat-voice
brew install portaudio
uv venv --python 3.12
uv pip install -e '.[pipecat]'
uv run uvicorn server:app --host 127.0.0.1 --port 7860
```

TipTour passes the saved Gemini API key to the localhost sidecar when starting a voice session. For standalone curl tests, export `GOOGLE_API_KEY` or `GEMINI_API_KEY`.

## Tool Policy

Pipecat should expose these function tools to its LLM:

- `tiptour_observe` -> `GET /v1/observe`
- `tiptour_active_skill` -> `GET /v1/skills/active`
- `tiptour_targets` -> `GET /v1/targets`
- `tiptour_plan_next_action` -> `POST /v1/plan-next-action`
- `tiptour_submit_workflow_plan` -> `POST /v1/workflow-plan`
- `tiptour_action_history` -> `GET /v1/action-history`
- `hermes_delegate` -> `POST http://127.0.0.1:8642/v1/chat/completions`

For direct visible UI actions, Pipecat should call TipTour itself. For long or ambiguous tasks, Pipecat should delegate to Hermes and let Hermes call TipTour tools.

## Action Rules

- Execute one desktop action at a time.
- Prefer `target_id` or `target_mark` from `/v1/targets` over fuzzy label matching.
- Use `/v1/plan-next-action` for visible clicks.
- Use `/v1/workflow-plan` for app launch, keys, typing, scrolling, and direct workflow steps.
- Do not guess raw coordinates from screenshots unless TipTour adds a specific screenshot-planning endpoint.
- Do not run Pipecat and Hermes as competing planners for the same turn.

## Intended Flow

1. User speaks to Pipecat.
2. Pipecat classifies the request:
   - simple visible click or one key/type action -> TipTour harness
   - multi-step workflow -> Hermes delegate
3. TipTour executes one action and returns validation/action history.
4. Pipecat speaks a short status update.
5. For long tasks, Hermes loops over TipTour observe/targets/action-history until finished.

This keeps TipTour as the best damn pointer engine and lets Pipecat/Hermes evolve independently.
