from __future__ import annotations

import asyncio
import importlib.metadata
import os
import time
import uuid
from collections import deque
from dataclasses import dataclass, field
from typing import Any, Literal

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

load_dotenv()

DEFAULT_TIPTOUR_BASE_URL = "http://127.0.0.1:19474"
DEFAULT_HERMES_BASE_URL = "http://127.0.0.1:8642"


class StartRequest(BaseModel):
    tiptour_base_url: str = Field(default=DEFAULT_TIPTOUR_BASE_URL)
    hermes_base_url: str = Field(default=DEFAULT_HERMES_BASE_URL)
    mode: Literal["gemini-live-local", "sidecar", "dev"] = "gemini-live-local"
    provider: str | None = "gemini-live"
    google_api_key: str | None = None


class ToolCallRequest(BaseModel):
    arguments: dict[str, Any] = Field(default_factory=dict)


class SidecarEvent(BaseModel):
    id: str
    type: str
    message: str
    timestamp: float
    payload: dict[str, Any] = Field(default_factory=dict)


@dataclass
class SidecarState:
    active: bool = False
    session_id: str | None = None
    started_at: float | None = None
    last_error: str | None = None
    tiptour_base_url: str = DEFAULT_TIPTOUR_BASE_URL
    hermes_base_url: str = DEFAULT_HERMES_BASE_URL
    mode: str = "sidecar"
    provider: str | None = None
    events: deque[SidecarEvent] = field(default_factory=lambda: deque(maxlen=80))
    lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    voice_task: asyncio.Task | None = None
    pipeline_task: Any | None = None


state = SidecarState()
app = FastAPI(title="TipTour Pipecat Voice Sidecar", version="0.1.0")


def pipecat_status() -> dict[str, Any]:
    try:
        version = importlib.metadata.version("pipecat-ai")
        installed = True
    except importlib.metadata.PackageNotFoundError:
        version = None
        installed = False

    import_ready = False
    import_error = None
    if installed:
        try:
            __import__("pipecat.pipeline.pipeline")
            __import__("pipecat.pipeline.runner")
            __import__("pipecat.pipeline.task")
            import_ready = True
        except Exception as exc:  # pragma: no cover - environment dependent
            import_error = str(exc)

    return {
        "installed": installed,
        "import_ready": import_ready,
        "version": version,
        "import_error": import_error,
        "local_audio_ready": local_audio_ready(),
    }


def local_audio_ready() -> bool:
    try:
        __import__("pyaudio")
        return True
    except Exception:
        return False


def emit(event_type: str, message: str, payload: dict[str, Any] | None = None) -> SidecarEvent:
    event = SidecarEvent(
        id=str(uuid.uuid4()),
        type=event_type,
        message=message,
        timestamp=time.time(),
        payload=payload or {},
    )
    state.events.append(event)
    return event


async def get_json(base_url: str, path: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=3.0) as client:
        response = await client.get(f"{base_url.rstrip('/')}{path}")
        response.raise_for_status()
        return response.json()


async def post_json(base_url: str, path: str, payload: dict[str, Any]) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=60.0) as client:
        response = await client.post(f"{base_url.rstrip('/')}{path}", json=payload)
        response.raise_for_status()
        return response.json()


async def tiptour_tool(tool_name: str, arguments: dict[str, Any]) -> dict[str, Any]:
    if tool_name == "tiptour_observe":
        return await get_json(state.tiptour_base_url, "/v1/observe")
    if tool_name == "tiptour_active_skill":
        return await get_json(state.tiptour_base_url, "/v1/skills/active")
    if tool_name == "tiptour_targets":
        return await get_json(state.tiptour_base_url, "/v1/targets")
    if tool_name == "tiptour_action_history":
        return await get_json(state.tiptour_base_url, "/v1/action-history")
    if tool_name == "tiptour_plan_next_action":
        return await post_json(state.tiptour_base_url, "/v1/plan-next-action", arguments)
    if tool_name == "tiptour_submit_workflow_plan":
        return await post_json(state.tiptour_base_url, "/v1/workflow-plan", arguments)
    if tool_name == "hermes_delegate":
        payload = {
            "model": "hermes-agent",
            "messages": arguments.get("messages")
            or [{"role": "user", "content": arguments.get("prompt", "")}],
            "stream": arguments.get("stream", False),
        }
        return await post_json(state.hermes_base_url, "/v1/chat/completions", payload)
    raise ValueError(f"Unknown tool: {tool_name}")


async def service_status(base_url: str, path: str) -> dict[str, Any]:
    try:
        payload = await get_json(base_url, path)
        return {"reachable": True, "payload": payload}
    except Exception as exc:
        return {"reachable": False, "error": str(exc)}


def tool_specs() -> list[dict[str, Any]]:
    return [
        {"name": "tiptour_observe", "method": "GET", "path": "/v1/observe"},
        {"name": "tiptour_active_skill", "method": "GET", "path": "/v1/skills/active"},
        {"name": "tiptour_targets", "method": "GET", "path": "/v1/targets"},
        {"name": "tiptour_action_history", "method": "GET", "path": "/v1/action-history"},
        {"name": "tiptour_plan_next_action", "method": "POST", "path": "/v1/plan-next-action"},
        {
            "name": "tiptour_submit_workflow_plan",
            "method": "POST",
            "path": "/v1/workflow-plan",
        },
        {"name": "hermes_delegate", "method": "POST", "path": "/v1/chat/completions"},
    ]


def build_pipecat_tools():
    from pipecat.adapters.schemas.function_schema import FunctionSchema
    from pipecat.adapters.schemas.tools_schema import ToolsSchema

    return ToolsSchema(
        standard_tools=[
            FunctionSchema(
                name="tiptour_observe",
                description="Observe the active macOS app and TipTour state.",
                properties={},
                required=[],
            ),
            FunctionSchema(
                name="tiptour_active_skill",
                description="Get the active TipTour app skill for the current app.",
                properties={},
                required=[],
            ),
            FunctionSchema(
                name="tiptour_targets",
                description="Get visible local grounding targets with target IDs and marks.",
                properties={},
                required=[],
            ),
            FunctionSchema(
                name="tiptour_action_history",
                description="Get recent TipTour action validation history.",
                properties={},
                required=[],
            ),
            FunctionSchema(
                name="tiptour_plan_next_action",
                description="Ask TipTour to ground and optionally execute one visible UI action.",
                properties={
                    "goal": {"type": "string"},
                    "app": {"type": "string"},
                    "target_label": {"type": "string"},
                    "target_id": {"type": "string"},
                    "target_mark": {"type": "integer"},
                    "action": {"type": "string"},
                    "execute": {"type": "boolean"},
                },
                required=["goal"],
            ),
            FunctionSchema(
                name="tiptour_submit_workflow_plan",
                description="Submit exactly one TipTour workflow step for app launch, key, type, click, or scroll actions.",
                properties={
                    "goal": {"type": "string"},
                    "app": {"type": "string"},
                    "steps": {"type": "array", "items": {"type": "object"}},
                },
                required=["goal", "steps"],
            ),
            FunctionSchema(
                name="hermes_delegate",
                description="Delegate a long-running task to Hermes instead of planning it in Pipecat.",
                properties={"prompt": {"type": "string"}},
                required=["prompt"],
            ),
        ]
    )


async def run_gemini_live_local_audio(google_api_key: str):
    from pipecat.frames.frames import LLMRunFrame
    from pipecat.pipeline.pipeline import Pipeline
    from pipecat.pipeline.runner import PipelineRunner
    from pipecat.pipeline.task import PipelineParams, PipelineTask
    from pipecat.processors.aggregators.llm_context import LLMContext
    from pipecat.processors.aggregators.llm_response_universal import (
        AssistantTurnStoppedMessage,
        LLMContextAggregatorPair,
        UserTurnStoppedMessage,
    )
    from pipecat.services.google.gemini_live.llm import GeminiLiveLLMService
    from pipecat.services.llm_service import FunctionCallParams
    from pipecat.transports.local.audio import LocalAudioTransport, LocalAudioTransportParams

    transport = LocalAudioTransport(
        LocalAudioTransportParams(audio_in_enabled=True, audio_out_enabled=True)
    )

    def make_tool_callback(tool_name: str):
        async def callback(params: FunctionCallParams):
            emit("tool.started", f"{tool_name} started.", {"tool": tool_name})
            try:
                result = await tiptour_tool(tool_name, params.arguments)
                emit("tool.completed", f"{tool_name} completed.", {"tool": tool_name})
                await params.result_callback(result)
            except Exception as exc:
                message = str(exc)
                emit("tool.failed", f"{tool_name} failed: {message}", {"tool": tool_name})
                await params.result_callback({"ok": False, "error": message})

        return callback

    system_instruction = """
    You are Pipecat running as TipTour's local voice sidecar.

    Talk naturally and briefly. TipTour is the macOS pointer, perception, and action engine.
    Do not guess desktop coordinates. Use TipTour tools for observe, targets, action history,
    and one desktop action at a time. For long cross-app or multi-step tasks, use hermes_delegate.
    """

    llm = GeminiLiveLLMService(
        api_key=google_api_key,
        voice_id="Aoede",
        system_instruction=system_instruction,
        tools=build_pipecat_tools(),
    )

    for tool in tool_specs():
        llm.register_function(tool["name"], make_tool_callback(tool["name"]))

    context = LLMContext()
    user_aggregator, assistant_aggregator = LLMContextAggregatorPair(context)

    @user_aggregator.event_handler("on_user_turn_stopped")
    async def on_user_turn_stopped(aggregator, strategy, message: UserTurnStoppedMessage):
        emit("transcript.user", message.content)

    @assistant_aggregator.event_handler("on_assistant_turn_stopped")
    async def on_assistant_turn_stopped(aggregator, message: AssistantTurnStoppedMessage):
        emit("transcript.assistant", message.content)

    pipeline = Pipeline(
        [
            transport.input(),
            user_aggregator,
            llm,
            transport.output(),
            assistant_aggregator,
        ]
    )
    pipeline_task = PipelineTask(
        pipeline,
        params=PipelineParams(enable_metrics=True, enable_usage_metrics=True),
    )
    state.pipeline_task = pipeline_task

    context.add_message(
        {
            "role": "developer",
            "content": "Say one short sentence that TipTour Pipecat voice is listening.",
        }
    )
    await pipeline_task.queue_frames([LLMRunFrame()])

    runner = PipelineRunner(handle_sigint=False)
    await runner.run(pipeline_task)


async def stop_voice_pipeline():
    if state.pipeline_task is not None:
        try:
            await state.pipeline_task.cancel()
        except Exception as exc:
            emit("session.warning", f"Pipeline cancel warning: {exc}")
        state.pipeline_task = None

    if state.voice_task is not None:
        state.voice_task.cancel()
        try:
            await state.voice_task
        except asyncio.CancelledError:
            pass
        except Exception as exc:
            emit("session.warning", f"Voice task stop warning: {exc}")
        state.voice_task = None


def voice_task_done(task: asyncio.Task):
    if task.cancelled():
        return

    try:
        task.result()
    except Exception as exc:
        state.active = False
        state.last_error = str(exc)
        emit("session.failed", f"Voice pipeline failed: {exc}")


@app.get("/health")
@app.get("/v1/health")
async def health() -> dict[str, Any]:
    tiptour = await service_status(state.tiptour_base_url, "/v1/health")
    return {
        "ok": True,
        "service": "tiptour-pipecat-voice",
        "active": state.active,
        "session_id": state.session_id,
        "mode": state.mode,
        "provider": state.provider,
        "last_error": state.last_error,
        "tiptour": tiptour,
        "hermes_base_url": state.hermes_base_url,
        "pipecat": pipecat_status(),
        "tools": [tool["name"] for tool in tool_specs()],
    }


@app.post("/v1/start")
async def start(request: StartRequest) -> dict[str, Any]:
    async with state.lock:
        if state.active:
            return await health()

        state.last_error = None
        state.session_id = state.session_id or str(uuid.uuid4())
        state.started_at = state.started_at or time.time()
        state.tiptour_base_url = request.tiptour_base_url.rstrip("/")
        state.hermes_base_url = request.hermes_base_url.rstrip("/")
        state.mode = request.mode
        state.provider = request.provider

        google_api_key = (
            request.google_api_key
            or os.environ.get("GOOGLE_API_KEY")
            or os.environ.get("GEMINI_API_KEY")
        )
        if not google_api_key:
            state.active = False
            state.last_error = "Missing GOOGLE_API_KEY/GEMINI_API_KEY for Pipecat Gemini Live."
            emit("session.failed", state.last_error)
            return await health()

        if not pipecat_status()["import_ready"]:
            state.active = False
            state.last_error = "Pipecat runtime is not import-ready. Install harnesses/pipecat-voice with the pipecat extra."
            emit("session.failed", state.last_error)
            return await health()

        if not local_audio_ready():
            state.active = False
            state.last_error = "Local audio is not ready. Install portaudio and pipecat-ai[local]."
            emit("session.failed", state.last_error)
            return await health()

        state.active = True
        state.voice_task = asyncio.create_task(run_gemini_live_local_audio(google_api_key))
        state.voice_task.add_done_callback(voice_task_done)
        emit(
            "session.started",
            "Pipecat Gemini Live local audio session started.",
            {
                "session_id": state.session_id,
                "mode": state.mode,
                "provider": state.provider,
            },
        )

    return await health()


@app.post("/v1/stop")
async def stop() -> dict[str, Any]:
    async with state.lock:
        old_session_id = state.session_id
        await stop_voice_pipeline()
        state.active = False
        state.session_id = None
        state.started_at = None
        emit("session.stopped", "Pipecat sidecar session stopped.", {"session_id": old_session_id})
    return await health()


@app.get("/v1/events")
async def events() -> dict[str, Any]:
    return {
        "ok": True,
        "active": state.active,
        "session_id": state.session_id,
        "events": [event.model_dump() for event in list(state.events)],
    }


@app.get("/v1/tools")
async def tools() -> dict[str, Any]:
    return {"ok": True, "tools": tool_specs()}


@app.post("/v1/tools/{tool_name}")
async def call_tool(tool_name: str, request: ToolCallRequest) -> dict[str, Any]:
    try:
        result = await tiptour_tool(tool_name, request.arguments)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except httpx.HTTPStatusError as exc:
        emit(
            "tool.failed",
            f"{tool_name} failed with HTTP {exc.response.status_code}.",
            {"tool": tool_name},
        )
        raise HTTPException(status_code=exc.response.status_code, detail=exc.response.text) from exc
    except httpx.HTTPError as exc:
        emit("tool.failed", f"{tool_name} could not reach its service.", {"tool": tool_name})
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    emit("tool.completed", f"{tool_name} completed.", {"tool": tool_name})
    return {"ok": True, "tool": tool_name, "result": result}
