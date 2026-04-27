import { YoutubeTranscript } from "youtube-transcript";

/**
 * TipTour Proxy Worker
 *
 * Thin Cloudflare Worker that proxies the Gemini API calls and the
 * YouTube transcript fetcher, so the app ships without raw API keys.
 * Keys are stored as Cloudflare secrets.
 *
 * Routes:
 *   GET  /gemini-live-key  → returns the Gemini API key so the app can
 *                            open a direct WebSocket to Gemini Live.
 *   POST /transcript       → Fetches a YouTube transcript by video ID.
 *   POST /match-label      → Multilingual label matcher used by the
 *                            in-app ElementResolver fallback.
 */

interface Env {
  GEMINI_API_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

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
      if (url.pathname === "/transcript") {
        return await handleTranscript(request);
      }

      if (url.pathname === "/match-label") {
        return await handleMatchLabel(request, env);
      }

      if (url.pathname === "/tutorial-chunk") {
        return await handleTutorialChunk(request, env);
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

/**
 * /match-label
 *
 * Body: { query: string, candidates: string[] }
 *
 * Returns the candidate label that best matches `query` semantically,
 * or null if nothing's a confident match. Used as a multilingual
 * fallback when the in-app AccessibilityTreeResolver can't find a
 * direct match because the LLM passed a label in the user's spoken
 * language while the AX tree has labels in the UI's display language
 * (e.g. user said "guardar" but the AX tree has "Save").
 *
 * Tiny prompt + tiny output → uses gemini-2.5-flash-lite for sub-300ms
 * latency. The whole point is "ask the model to bridge a translation
 * miss," not deep reasoning.
 */
async function handleMatchLabel(request: Request, env: Env): Promise<Response> {
  const { query, candidates } = await request.json() as {
    query: string;
    candidates: string[];
  };

  if (!query || !Array.isArray(candidates) || candidates.length === 0) {
    return new Response(JSON.stringify({ match: null }), {
      headers: { "content-type": "application/json" },
    });
  }

  // Cap candidates we feed the model — AX trees can have hundreds of
  // labels and we only need a focused list for the model to choose from.
  const cappedCandidates = candidates.slice(0, 80);

  const prompt = [
    `The user wants to find a UI element matching this label: "${query}"`,
    `Here are the labels actually present in the UI's accessibility tree (one per line):`,
    cappedCandidates.map((c) => `- ${c}`).join("\n"),
    ``,
    `Which one matches the user's intent?`,
    `The query may be in a different language than the candidates (e.g. query is Spanish, candidates are English).`,
    `Match by MEANING, not by string similarity.`,
    ``,
    `Reply with JSON only: { "match": "<exact candidate label>" } if there's a clear match, or { "match": null } if there isn't.`,
    `Use the EXACT spelling and casing from the candidate list.`,
  ].join("\n");

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${env.GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: {
          temperature: 0.0,
          maxOutputTokens: 128,
          responseMimeType: "application/json",
        },
      }),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/match-label] Gemini error ${response.status}: ${errorBody}`);
    return new Response(JSON.stringify({ match: null }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  const data = await response.text();
  return new Response(data, {
    status: 200,
    headers: { "content-type": "application/json" },
  });
}

/**
 * /tutorial-chunk
 *
 * Body: { transcriptChunk: string, screenshotBase64?: string }
 *
 * Called from the app every time the tutorial swaps from .video to
 * .instruction. Takes the raw transcript text from the 10-second
 * segment that just played plus an optional screenshot of the user's
 * actual screen, and returns:
 *   - a tight 1-2 sentence imperative instruction ("Click File → New")
 *   - optionally an `elementLabel` the app should fly the cursor to
 *     (must be visible text from the user's screenshot)
 *
 * Uses gemini-2.5-flash with structured output so the response is
 * always parseable JSON. ~1-3s typical latency.
 */
async function handleTutorialChunk(request: Request, env: Env): Promise<Response> {
  const body = await request.json() as {
    transcriptChunk: string;
    screenshotBase64?: string;
  };

  const systemInstruction = `
You are watching the user follow a YouTube software tutorial. The
video just played a short segment with this transcript. Your job is
to translate the narrator's words into a tight, imperative
instruction the user can act on right now.

Rules:
- 1-2 SHORT sentences max. Direct imperative voice ("Click File → New").
- NO filler ("Now you can...", "What we want to do is...", "Let's...").
- Reference specific menus / buttons / fields by name.
- Use → to chain steps ("Click File → New → Project").
- If the segment is mid-explanation with no clear action, return a
  one-line summary of what the narrator just covered.

If you can identify a SPECIFIC visible UI element on the user's
screenshot that they should click for this step, also return the
element's exact visible label as elementLabel. The label must be
text the user can SEE on their screen RIGHT NOW. If you can't be
confident, return null.

Return STRICT JSON only, no markdown:
  { "instruction": "<imperative sentence>", "elementLabel": "<exact label>" or null }
`.trim();

  const contentParts: any[] = [
    { text: `Transcript of the segment that just played:\n"${body.transcriptChunk}"` },
  ];
  if (body.screenshotBase64) {
    contentParts.push({
      inlineData: { mimeType: "image/jpeg", data: body.screenshotBase64 },
    });
  }

  const response = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_API_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: systemInstruction }] },
        contents: [{ parts: contentParts }],
        generationConfig: {
          temperature: 0.1,
          maxOutputTokens: 256,
          responseMimeType: "application/json",
          responseSchema: {
            type: "object",
            properties: {
              instruction: { type: "string" },
              elementLabel: { type: "string" },
            },
            required: ["instruction"],
          },
        },
      }),
    }
  );

  if (!response.ok) {
    const errorBody = await response.text();
    console.error(`[/tutorial-chunk] Gemini error ${response.status}: ${errorBody}`);
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
