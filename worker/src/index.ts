import { YoutubeTranscript } from "youtube-transcript";

/**
 * TipTour Proxy Worker
 *
 * Proxies requests to Claude and ElevenLabs APIs so the app never
 * ships with raw API keys. Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   POST /chat  → Anthropic Messages API (streaming)
 *   POST /tts   → ElevenLabs TTS API
 */

interface Env {
  ANTHROPIC_API_KEY: string;
  ELEVENLABS_API_KEY: string;
  ELEVENLABS_VOICE_ID: string;
  GEMINI_API_KEY: string;
  OPENROUTER_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // GET endpoints — currently just /gemini-live-key
    if (request.method === "GET") {
      if (url.pathname === "/gemini-live-key") {
        return handleGeminiLiveKey(env);
      }
      return new Response("Method not allowed", { status: 405 });
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/chat") {
        return await handleChat(request, env);
      }

      if (url.pathname === "/tts") {
        return await handleTTS(request, env);
      }

      if (url.pathname === "/chat-fast") {
        return await handleChatFast(request, env);
      }

      if (url.pathname === "/generate-guide") {
        return await handleGenerateGuide(request, env);
      }

      if (url.pathname === "/transcript") {
        return await handleTranscript(request);
      }
    } catch (error) {
      console.error(`[${url.pathname}] Unhandled error:`, error);
      return new Response(
        JSON.stringify({ error: String(error) }),
        { status: 500, headers: { "content-type": "application/json" } }
      );
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleChat(request: Request, env: Env): Promise<Response> {
  const body = await request.text();

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": env.ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body,
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat] Anthropic API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "text/event-stream",
      "cache-control": "no-cache",
    },
  });
}

async function handleTranscript(request: Request): Promise<Response> {
  const { videoID } = await request.json() as { videoID: string };

  try {
    const segments = await YoutubeTranscript.fetchTranscript(videoID);

    // Format as timestamped lines
    const transcript = segments.map((s: any) => {
      const mins = Math.floor(s.offset / 60000);
      const secs = Math.floor((s.offset % 60000) / 1000);
      return `[${mins}:${secs.toString().padStart(2, "0")}] ${s.text}`;
    }).join("\n");

    console.log(`[/transcript] Got ${segments.length} segments, ${transcript.length} chars`);

    return new Response(JSON.stringify({ transcript }), {
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    console.error("[/transcript] Failed:", e);
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 404,
      headers: { "content-type": "application/json" },
    });
  }
}

async function handleGenerateGuide(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as { transcript: string };

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: body.transcript }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 65536 },
      }),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/generate-guide] Gemini error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

async function handleChatFast(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const parsed = JSON.parse(body);

  // Override model to use a fast one via OpenRouter
  parsed.model = parsed.model || "google/gemma-4-31b-it";

  const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${env.OPENROUTER_API_KEY}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://tiptour.io",
      "X-Title": "TipTour",
    },
    body: JSON.stringify(parsed),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/chat-fast] OpenRouter error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "application/json",
      "cache-control": "no-cache",
    },
  });
}

/**
 * Returns the Gemini API key so the app can open a direct WebSocket
 * to the Gemini Live API. Cloudflare Workers can't cleanly proxy
 * WebSocket traffic to Google's endpoint, so the app connects directly.
 *
 * SECURITY NOTE: This endpoint exposes the raw API key to any client
 * that hits it. For production, replace this with Gemini's ephemeral
 * token API (v1alpha) once it's stable, or add a shared-secret header
 * the app must send.
 */
function handleGeminiLiveKey(env: Env): Response {
  if (!env.GEMINI_API_KEY) {
    return new Response(
      JSON.stringify({ error: "GEMINI_API_KEY not configured" }),
      { status: 500, headers: { "content-type": "application/json" } }
    );
  }
  return new Response(
    JSON.stringify({ apiKey: env.GEMINI_API_KEY }),
    { headers: { "content-type": "application/json", "cache-control": "no-cache" } }
  );
}

async function handleTTS(request: Request, env: Env): Promise<Response> {
  const body = await request.text();
  const voiceId = env.ELEVENLABS_VOICE_ID;

  const response = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body,
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tts] ElevenLabs API error ${response.status}: ${errorBody}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  return new Response(response.body, {
    status: response.status,
    headers: {
      "content-type": response.headers.get("content-type") || "audio/mpeg",
    },
  });
}
