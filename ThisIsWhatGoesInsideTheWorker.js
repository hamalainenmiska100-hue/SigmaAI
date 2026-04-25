/**
 * Cloudflare Pages Function / Worker proxy for Sigma.
 *
 * Route expected by Flutter app:
 *   POST https://<your-domain>/chat
 *
 * Required secret env var:
 *   NVIDIA_API_KEY (or NIM_API_KEY)
 *
 * Optional env vars:
 *   SYSTEM_INSTRUCTION
 *   SYSTEM_INSTRUCTION_NORMAL
 *   SYSTEM_INSTRUCTION_UNHINGED
 *   SYSTEM_INSTRUCTION_SPICY
 *   SUMMARY_ANALYZER_SYSTEM_PROMPT
 *   CORS_ALLOW_ORIGIN (default: *)
 */

const NVIDIA_CHAT_COMPLETIONS_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const TEXT_MODEL = 'mistralai/mistral-nemotron';
const VISION_MODEL = 'meta/llama-3.2-11b-vision-instruct';
const VISION_PROMPT = 'Describe what is in this image in detail so it can be used as context for a separate text-only assistant.';

const WIKIPEDIA_API_URL = 'https://en.wikipedia.org/w/api.php';
const WIKIDATA_SEARCH_API_URL = 'https://www.wikidata.org/w/api.php';
const WIKIDATA_ENTITY_DATA_BASE_URL = 'https://www.wikidata.org/wiki/Special:EntityData';
const SEARCH_QUERY_SYSTEM_PROMPT = `You generate concise web search queries for Wikipedia and Wikidata.\nReturn ONLY valid JSON with this exact shape:\n{"wikipedia": ["query 1", "query 2"], "wikidata": ["query 1", "query 2"]}\nRules:\n- Keep each query directly relevant to the user request.\n- Use 1 to 3 queries per array.\n- Prefer entities, facts, events, places, people, products, laws, standards, and dates when relevant.\n- Keep queries short and specific.\n- No markdown, no prose, no explanations.`;
const WIKIPEDIA_LATEST_HINT_REGEX = /\b(latest|today|current|recent|newest|update|updated|as of|right now|this week|this month|this year)\b/i;

const MAX_MESSAGE_CHARS = 16_000;
const MAX_HISTORY_ITEMS = 40;
const MAX_IMAGE_URL_CHARS = 2_000_000;
const UPSTREAM_TIMEOUT_MS = 55_000;
const WIKI_FETCH_TIMEOUT_MS = 8_000;
const SUMMARY_REFRESH_MS = 5 * 60 * 1000;
const MAX_SUMMARY_PROMPT_CHARS = 24_000;
const MAX_LOG_SCAN = 120;
const FIREBASE_TIMEOUT_MS = 5_000;

const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyDyox96frB3esePugDEJrMLipIAOO61t88',
  authDomain: 'sigmaai-740d8.firebaseapp.com',
  projectId: 'sigmaai-740d8',
  storageBucket: 'sigmaai-740d8.firebasestorage.app',
  messagingSenderId: '92035951796',
  appId: '1:92035951796:web:1d893cf52de8bb8ec87be1',
  measurementId: 'G-GNPKF0TCGX',
};
const FIREBASE_DATABASE_URL = 'https://sigmaai-740d8-default-rtdb.europe-west1.firebasedatabase.app';
const SUMMARY_ANALYZER_PROMPT = `You are a training-data summarizer for Sigma AI.
Analyze chat logs and produce compact fine-tuning guidance.
Return plain text only with sections:
1) User goals and recurring intents
2) Quality failures to fix
3) Preferred response style
4) Safety boundaries
5) Prompt additions for future system instruction
Keep it under 700 words and directly actionable.`;

let firebaseAuthState = {
  idToken: '',
  uid: '',
  expiresAt: 0,
};
const modeSummaryCache = new Map();

export async function onRequestPost(context) {
  return handleChatRequest(context.request, context.env, context?.waitUntil?.bind(context));
}

export async function onRequestOptions(context) {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(context?.request, context?.env),
  });
}

export default {
  async fetch(request, env, executionContext) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(request, env),
      });
    }

    if (url.pathname !== '/chat') {
      return withCors(json({ error: 'Not found' }, 404), request, env);
    }

    if (request.method !== 'POST') {
      return withCors(json({ error: 'Method not allowed' }, 405), request, env);
    }

    return handleChatRequest(request, env, executionContext?.waitUntil?.bind(executionContext));
  },
};

async function handleChatRequest(request, env, waitUntil) {
  const contentType = (request.headers.get('content-type') ?? '').toLowerCase();
  if (!contentType.includes('application/json')) {
    return withCors(json({ error: 'Content-Type must be application/json' }, 415), request, env);
  }

  let payload;
  try {
    payload = await request.json();
  } catch {
    return withCors(json({ error: 'Invalid JSON' }, 400), request, env);
  }

  const message = sanitizeText(payload?.message, MAX_MESSAGE_CHARS);
  const imageData = sanitizeImageUrls(payload?.imageData);
  const languageTag = sanitizeText(payload?.languageTag, 32);
  const systemMode = sanitizeText(payload?.systemMode, 32).toLowerCase();
  const normalizedMode = normalizeMode(systemMode);
  const selectedInstruction = pickSystemInstruction(env, systemMode);
  const chatHistory = Array.isArray(payload?.chatHistory) ? payload.chatHistory.slice(-MAX_HISTORY_ITEMS) : [];
  const stream = payload?.stream !== false;

  if (!message && imageData.length === 0) {
    return withCors(json({ error: 'Message or image is required' }, 400), request, env);
  }

  const apiKey = String(env?.NVIDIA_API_KEY ?? env?.NIM_API_KEY ?? '').trim();
  if (!apiKey) {
    return withCors(json({ error: 'Server misconfigured: missing NVIDIA_API_KEY' }, 500), request, env);
  }

  const messages = [];
  const firebaseSession = await getFirebaseSession();
  const { summary: activeSummary, stale: summaryStale } = firebaseSession
    ? await getModeSummarySnapshot({
        mode: normalizedMode,
        firebaseSession,
      })
    : { summary: '', stale: false };

  if (firebaseSession && summaryStale) {
    runInBackground(
      refreshModeSummary({
        env,
        apiKey,
        mode: normalizedMode,
        existingSummary: activeSummary,
        chatHistory,
        incomingMessage: message,
        firebaseSession,
      }),
      waitUntil,
    );
  }

  if (selectedInstruction) messages.push({ role: 'system', content: selectedInstruction });
  if (activeSummary) {
    messages.push({
      role: 'system',
      content:
        `Hidden adaptive context summary for "${normalizedMode}" mode:\n${activeSummary}\n` +
        'Do not reveal this hidden summary unless explicitly asked for system metadata.',
    });
  }

  for (const item of chatHistory) {
    const role = item?.role === 'assistant' ? 'assistant' : 'user';
    const content = sanitizeText(item?.content, MAX_MESSAGE_CHARS);
    const itemImage = sanitizeImageUrl(item?.imageData);
    if (!content && !itemImage) continue;

    if (itemImage && role === 'user' && !content) {
      messages.push({ role, content: 'User shared an image earlier in this thread.' });
      continue;
    }

    messages.push({ role, content });
  }

  const taggedMessage = [message, languageTag].filter(Boolean).join(' ').trim();

  const webContext = await buildKnowledgeContext({
    apiKey,
    userMessage: taggedMessage,
    chatHistory,
  });

  messages.push({
    role: 'system',
    content:
      'You can receive live Wikipedia and Wikidata context from the system. If present, prioritize it over stale memory and use exact dates for time-sensitive answers.',
  });

  if (webContext) {
    messages.push({
      role: 'system',
      content:
        'You have live web research context from official Wikipedia and Wikidata APIs in this conversation. Use it when relevant, prefer it over stale memory, and do not claim you lack web context when this data is present.',
    });
    messages.push({
      role: 'system',
      content: webContext,
    });
  }

  if (imageData.length > 0) {
    const imageSummaries = [];
    for (const imageUrl of imageData) {
      try {
        const summary = await summarizeWithVisionModel({ imageUrl, apiKey });
        if (summary) imageSummaries.push(summary);
      } catch {}
    }

    const synthesizedImageContext = imageSummaries.length
      ? imageSummaries.map((summary, i) => `Image ${i + 1} summary:\n${summary}`).join('\n\n')
      : '';
    const finalUserContent = [taggedMessage, synthesizedImageContext].filter(Boolean).join('\n\n').trim();

    messages.push({
      role: 'user',
      content: finalUserContent || 'User shared image(s).',
    });
  } else {
    messages.push({ role: 'user', content: taggedMessage });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('upstream-timeout'), UPSTREAM_TIMEOUT_MS);

  let upstreamResponse;
  try {
    upstreamResponse = await fetch(NVIDIA_CHAT_COMPLETIONS_URL, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: TEXT_MODEL,
        messages,
        stream,
        temperature: 0.2,
      }),
      signal: controller.signal,
      keepalive: true,
    });
  } catch {
    clearTimeout(timeout);
    return withCors(json({ error: 'Upstream provider unreachable' }, 502), request, env);
  }

  if (!stream) {
    clearTimeout(timeout);
    if (!upstreamResponse.ok) {
      const details = await safeJson(upstreamResponse);
      return withCors(json({ error: 'Upstream provider error', details }, 502), request, env);
    }

    const data = await safeJson(upstreamResponse);
    const content = extractTextContent(data);
    if (firebaseSession) {
      runInBackground(
        logConversationEvent({
          firebaseSession,
          mode: normalizedMode,
          payload: buildLogPayload({
            request,
            message,
            taggedMessage,
            reply: content,
            chatHistory,
            imageCount: imageData.length,
          }),
        }),
        waitUntil,
      );
    }
    return withCors(json({ type: 'message', content }), request, env);
  }

  if (!upstreamResponse.ok || !upstreamResponse.body) {
    clearTimeout(timeout);
    const details = await safeJson(upstreamResponse);
    return withCors(json({ error: 'Upstream provider error', details }, 502), request, env);
  }

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();
  let fullAssistantOutput = '';

  const transformed = new ReadableStream({
    async start(streamController) {
      const reader = upstreamResponse.body.getReader();
      let buffer = '';

      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          buffer += decoder.decode(value, { stream: true });

          let splitIndex = buffer.indexOf('\n\n');
          while (splitIndex !== -1) {
            const rawEvent = buffer.slice(0, splitIndex);
            buffer = buffer.slice(splitIndex + 2);

            const delta = extractDeltaFromEvent(rawEvent);
            if (delta) {
              fullAssistantOutput += delta;
              streamController.enqueue(
                encoder.encode(`data: ${JSON.stringify({ type: 'delta', delta })}\n\n`),
              );
            }

            if (rawEvent.includes('data: [DONE]')) {
              streamController.enqueue(encoder.encode('data: [DONE]\n\n'));
              streamController.close();
              return;
            }

            splitIndex = buffer.indexOf('\n\n');
          }
        }

        streamController.enqueue(encoder.encode('data: [DONE]\n\n'));
        streamController.close();
      } catch {
        streamController.error(new Error('Streaming interrupted'));
      } finally {
        if (firebaseSession) {
          runInBackground(
            logConversationEvent({
              firebaseSession,
              mode: normalizedMode,
              payload: buildLogPayload({
                request,
                message,
                taggedMessage,
                reply: fullAssistantOutput,
                chatHistory,
                imageCount: imageData.length,
              }),
            }),
            waitUntil,
          );
        }
        clearTimeout(timeout);
        reader.releaseLock();
      }
    },
    cancel() {
      clearTimeout(timeout);
      controller.abort('client-disconnect');
    },
  });

  return new Response(transformed, {
    status: 200,
    headers: {
      ...corsHeaders(request, env),
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store, no-transform',
      connection: 'keep-alive',
      'x-accel-buffering': 'no',
    },
  });
}

async function buildKnowledgeContext({ apiKey, userMessage, chatHistory }) {
  if (!userMessage) return '';

  const queryPlan = await generateWikimediaQueries({ apiKey, userMessage, chatHistory });
  if (!queryPlan.wikipedia.length && !queryPlan.wikidata.length) {
    return '';
  }

  const wikipediaResults = await searchWikipedia(queryPlan.wikipedia);
  const wikidataQueries = queryPlan.wikidata.length
    ? queryPlan.wikidata
    : wikipediaResults.map((item) => item.title).slice(0, 3);
  const wikidataResults = await searchWikidata(wikidataQueries);

  if (!wikipediaResults.length && !wikidataResults.length) {
    return '';
  }

  const wikiLines = wikipediaResults.map((item, index) => {
    const summary = item.snippet ? ` — ${item.snippet}` : '';
    const seenAt = item.timestamp ? ` [indexed: ${item.timestamp}]` : '';
    return `${index + 1}. ${item.title}${summary}${seenAt} (URL: ${item.url})`;
  });

  const wikidataLines = wikidataResults.map((item, index) => {
    const description = item.description ? ` — ${item.description}` : '';
    const aliases = item.aliases.length ? ` [aliases: ${item.aliases.join(', ')}]` : '';
    return `${index + 1}. ${item.label} (${item.id})${description}${aliases} (URL: ${item.url})`;
  });

  const sections = [`Live Wikimedia context generated at ${new Date().toISOString()}:`];
  if (wikiLines.length) {
    sections.push(['Wikipedia results (official API):', ...wikiLines].join('\n'));
  }
  if (wikidataLines.length) {
    sections.push(['Wikidata results (official API):', ...wikidataLines].join('\n'));
  }

  return sections.join('\n\n');
}

async function generateWikimediaQueries({ apiKey, userMessage, chatHistory }) {
  const recentContext = Array.isArray(chatHistory)
    ? chatHistory
        .slice(-4)
        .map((item) => `${item?.role === 'assistant' ? 'assistant' : 'user'}: ${sanitizeText(item?.content, 400)}`)
        .filter(Boolean)
        .join('\n')
    : '';

  const prompt = [
    'User request:',
    userMessage,
    recentContext ? '\nRecent chat context:\n' + recentContext : '',
  ]
    .filter(Boolean)
    .join('\n');

  let raw = '';
  try {
    raw = await runTextModel({
      apiKey,
      systemPrompt: SEARCH_QUERY_SYSTEM_PROMPT,
      userPrompt: prompt,
      temperature: 0,
      maxTokens: 200,
    });
  } catch {
    return fallbackSearchQueries(userMessage);
  }

  const parsed = parseQueryPlan(raw);
  if (parsed.wikipedia.length || parsed.wikidata.length) {
    return parsed;
  }

  return fallbackSearchQueries(userMessage);
}

function parseQueryPlan(raw) {
  const cleaned = sanitizeText(raw, 4_000);
  if (!cleaned) return { wikipedia: [], wikidata: [] };

  const candidates = [
    cleaned,
    stripCodeFences(cleaned),
    extractJsonObject(cleaned),
    autoFixJsonLike(cleaned),
    autoFixJsonLike(extractJsonObject(cleaned)),
  ].filter(Boolean);

  for (const candidate of candidates) {
    const parsed = tryParseQueryPlan(candidate);
    if (parsed.wikipedia.length || parsed.wikidata.length) {
      return parsed;
    }
  }

  const fallbackFromText = parseQueryPlanFromLooseText(cleaned);
  if (fallbackFromText.wikipedia.length || fallbackFromText.wikidata.length) {
    return fallbackFromText;
  }

  return { wikipedia: [], wikidata: [] };
}

function tryParseQueryPlan(candidate) {
  try {
    const parsed = JSON.parse(candidate);
    return normalizeQueryPlan(parsed);
  } catch {
    return { wikipedia: [], wikidata: [] };
  }
}

function normalizeQueryPlan(input) {
  const wikipedia = normalizeQueryArray(input?.wikipedia);
  const wikidata = normalizeQueryArray(input?.wikidata);
  return { wikipedia, wikidata };
}

function normalizeQueryArray(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => sanitizeText(entry, 140))
    .filter(Boolean)
    .slice(0, 3);
}

function stripCodeFences(value) {
  return String(value ?? '')
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```$/i, '')
    .trim();
}

function extractJsonObject(value) {
  const text = String(value ?? '');
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) return '';
  return text.slice(start, end + 1).trim();
}

function autoFixJsonLike(value) {
  const text = String(value ?? '').trim();
  if (!text) return '';

  return text
    .replace(/^[^{[]+/, '')
    .replace(/[^}\]]+$/, '')
    .replace(/([,{]\s*)'([^']+?)'\s*:/g, '$1"$2":')
    .replace(/:\s*'([^']*?)'/g, ': "$1"')
    .replace(/,\s*([}\]])/g, '$1')
    .trim();
}

function parseQueryPlanFromLooseText(value) {
  const lines = String(value ?? '')
    .split('\n')
    .map((line) => line.replace(/^[-*\d.\s]+/, '').trim())
    .filter(Boolean);

  const picked = lines.filter((line) => line.length <= 140).slice(0, 3);
  return {
    wikipedia: picked,
    wikidata: picked,
  };
}

function fallbackSearchQueries(userMessage) {
  const base = sanitizeText(userMessage, 140);
  if (!base) return { wikipedia: [], wikidata: [] };

  const compact = base.replace(/\s+/g, ' ').trim();
  const withoutPunctuation = compact.replace(/[!?.,:;()\[\]{}]/g, ' ');
  const titleCaseChunks = withoutPunctuation
    .split(/\s+/)
    .filter((token) => /^[A-Z][a-z0-9-]+$/.test(token))
    .slice(0, 4);
  const recentHint = WIKIPEDIA_LATEST_HINT_REGEX.test(base) ? ' latest' : '';
  const focused = titleCaseChunks.join(' ').trim();

  return {
    wikipedia: uniqueNonEmpty([`${compact}${recentHint}`.trim(), focused && `${focused}${recentHint}`.trim()]),
    wikidata: uniqueNonEmpty([compact, focused]),
  };
}

async function searchWikipedia(queries) {
  const uniqueQueries = uniqueNonEmpty(queries).slice(0, 3);
  const results = [];

  for (const query of uniqueQueries) {
    const url = new URL(WIKIPEDIA_API_URL);
    url.searchParams.set('action', 'query');
    url.searchParams.set('format', 'json');
    url.searchParams.set('list', 'search');
    url.searchParams.set('utf8', '1');
    url.searchParams.set('origin', '*');
    url.searchParams.set('srlimit', '3');
    url.searchParams.set('srsearch', query);

    const data = await fetchWithTimeoutJson(url.toString(), WIKI_FETCH_TIMEOUT_MS);
    const items = data?.query?.search;
    if (!Array.isArray(items)) continue;

    for (const item of items) {
      const title = sanitizeText(item?.title, 200);
      if (!title) continue;
      const snippet = sanitizeText(stripHtml(item?.snippet), 240);
      const timestamp = sanitizeText(item?.timestamp, 40);
      results.push({
        title,
        snippet,
        timestamp,
        url: `https://en.wikipedia.org/wiki/${encodeURIComponent(title.replace(/\s+/g, '_'))}`,
      });
      if (results.length >= 6) return dedupeBy(results, (entry) => entry.title.toLowerCase());
    }
  }

  return dedupeBy(results, (entry) => entry.title.toLowerCase());
}

async function searchWikidata(queries) {
  const uniqueQueries = uniqueNonEmpty(queries).slice(0, 3);
  const results = [];

  for (const query of uniqueQueries) {
    const url = new URL(WIKIDATA_SEARCH_API_URL);
    url.searchParams.set('action', 'wbsearchentities');
    url.searchParams.set('format', 'json');
    url.searchParams.set('language', 'en');
    url.searchParams.set('limit', '3');
    url.searchParams.set('origin', '*');
    url.searchParams.set('search', query);

    const data = await fetchWithTimeoutJson(url.toString(), WIKI_FETCH_TIMEOUT_MS);
    const items = data?.search;
    if (!Array.isArray(items)) continue;

    const resolvedItems = await Promise.all(
      items.map(async (item) => {
        const id = sanitizeText(item?.id, 32);
        const label = sanitizeText(item?.label, 200);
        if (!id || !label) return null;

        const entityDetails = await fetchWikidataEntityAliases(id);
        return {
          id,
          label,
          description: sanitizeText(item?.description, 240),
          aliases: entityDetails,
          url: sanitizeText(item?.concepturi, 400) || `https://www.wikidata.org/wiki/${id}`,
        };
      }),
    );

    for (const resolved of resolvedItems) {
      if (!resolved) continue;
      results.push(resolved);
      if (results.length >= 6) return dedupeBy(results, (entry) => entry.id);
    }
  }

  return dedupeBy(results, (entry) => entry.id);
}

async function fetchWikidataEntityAliases(entityId) {
  const url = `${WIKIDATA_ENTITY_DATA_BASE_URL}/${encodeURIComponent(entityId)}.json`;
  const data = await fetchWithTimeoutJson(url, WIKI_FETCH_TIMEOUT_MS);
  const aliases = data?.entities?.[entityId]?.aliases?.en;
  if (!Array.isArray(aliases)) return [];

  return aliases
    .map((item) => sanitizeText(item?.value, 80))
    .filter(Boolean)
    .slice(0, 3);
}

async function fetchWithTimeoutJson(url, timeoutMs) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('timeout'), timeoutMs);

  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
        'User-Agent': 'SigmaAI/1.0 (https://github.com/sigmaai/sigma)',
      },
      signal: controller.signal,
      keepalive: true,
    });

    if (!response.ok) {
      return null;
    }

    return await safeJson(response);
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function uniqueNonEmpty(values) {
  const seen = new Set();
  const unique = [];

  for (const value of values ?? []) {
    const cleaned = sanitizeText(value, 160);
    if (!cleaned) continue;
    const key = cleaned.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(cleaned);
  }

  return unique;
}

function dedupeBy(items, keyFn) {
  const seen = new Set();
  const output = [];
  for (const item of items) {
    const key = keyFn(item);
    if (!key || seen.has(key)) continue;
    seen.add(key);
    output.push(item);
  }
  return output;
}

function stripHtml(value) {
  return String(value ?? '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();
}

async function runTextModel({ apiKey, systemPrompt, userPrompt, temperature = 0.2, maxTokens = 500 }) {
  const response = await fetch(NVIDIA_CHAT_COMPLETIONS_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: TEXT_MODEL,
      stream: false,
      temperature,
      max_tokens: maxTokens,
      messages: [
        { role: 'system', content: sanitizeText(systemPrompt, 4_000) },
        { role: 'user', content: sanitizeText(userPrompt, MAX_MESSAGE_CHARS) },
      ],
    }),
    keepalive: true,
  });

  if (!response.ok) {
    throw new Error('query-model-failed');
  }

  const data = await safeJson(response);
  return sanitizeText(extractTextContent(data), 4_000);
}

function pickSystemInstruction(env, mode) {
  const normalized = String(mode ?? '').trim().toLowerCase();

  if (normalized === 'unhinged') {
    return sanitizeText(env?.SYSTEM_INSTRUCTION_UNHINGED, 4_000);
  }

  if (normalized === 'spicy') {
    return sanitizeText(env?.SYSTEM_INSTRUCTION_SPICY, 4_000);
  }

  if (normalized === 'normal') {
    return sanitizeText(env?.SYSTEM_INSTRUCTION_NORMAL, 4_000);
  }

  return sanitizeText(env?.SYSTEM_INSTRUCTION_NORMAL ?? env?.SYSTEM_INSTRUCTION, 4_000);
}

function normalizeMode(mode) {
  const normalized = String(mode ?? '').trim().toLowerCase();
  if (normalized === 'unhinged') return 'UNHINGED';
  if (normalized === 'spicy') return 'SPICY';
  return 'NORMAL';
}

async function getFirebaseSession() {
  const now = Date.now();
  if (firebaseAuthState.idToken && firebaseAuthState.expiresAt - 15_000 > now) {
    return firebaseAuthState;
  }

  const signInUrl =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=' +
    encodeURIComponent(FIREBASE_CONFIG.apiKey);

  try {
    const response = await withRetry(() =>
      fetchWithTimeout(signInUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ returnSecureToken: true }),
        keepalive: true,
      }),
    );
    if (!response || !response.ok) return null;
    const data = await safeJson(response);
    const idToken = sanitizeText(data?.idToken, 2_000);
    const uid = sanitizeText(data?.localId, 128);
    const expiresInSec = Number.parseInt(String(data?.expiresIn ?? '3600'), 10);
    if (!idToken || !uid) return null;

    firebaseAuthState = {
      idToken,
      uid,
      expiresAt: now + Math.max(60, Number.isFinite(expiresInSec) ? expiresInSec : 3600) * 1000,
    };
    return firebaseAuthState;
  } catch {
    return null;
  }
}

async function getModeSummarySnapshot({ mode, firebaseSession }) {
  const cached = modeSummaryCache.get(mode);
  if (cached && Date.now() - cached.updatedAt < SUMMARY_REFRESH_MS) {
    return {
      summary: sanitizeText(cached.summary, 6_000),
      stale: false,
    };
  }

  const summaryPath = `aiSummary/${mode}`;
  const existingSummary = await firebaseRead(summaryPath, firebaseSession.idToken);
  const lastUpdated = Number(existingSummary?.updatedAt ?? 0);
  const currentText = sanitizeText(existingSummary?.summary, 6_000);
  const stale = !lastUpdated || Date.now() - lastUpdated >= SUMMARY_REFRESH_MS;
  if (currentText) {
    modeSummaryCache.set(mode, { summary: currentText, updatedAt: lastUpdated || Date.now() });
  }
  return {
    summary: currentText,
    stale,
  };
}

async function refreshModeSummary({
  env,
  apiKey,
  mode,
  existingSummary,
  chatHistory,
  incomingMessage,
  firebaseSession,
}) {
  const summary = await buildModeSummary({
    env,
    apiKey,
    mode,
    existingSummary,
    chatHistory,
    incomingMessage,
    firebaseSession,
  });

  if (summary) {
    const updatedAt = Date.now();
    await firebasePatch(
      `aiSummary/${mode}`,
      {
        mode,
        summary,
        updatedAt,
        analyzerModel: TEXT_MODEL,
      },
      firebaseSession.idToken,
    );
    modeSummaryCache.set(mode, { summary, updatedAt });
  }
}

async function buildModeSummary({
  env,
  apiKey,
  mode,
  existingSummary,
  chatHistory,
  incomingMessage,
  firebaseSession,
}) {
  const logs = await fetchRecentModeLogs(mode, firebaseSession.idToken);
  const compactLogs = logs
    .slice(-MAX_LOG_SCAN)
    .map((item) => {
      const prompt = sanitizeText(item?.request?.prompt, 800);
      const answer = sanitizeText(item?.response?.text, 800);
      if (!prompt && !answer) return '';
      return `user: ${prompt}\nassistant: ${answer}`;
    })
    .filter(Boolean)
    .join('\n\n');

  const recentContext = Array.isArray(chatHistory)
    ? chatHistory
        .slice(-6)
        .map((item) => `${item?.role === 'assistant' ? 'assistant' : 'user'}: ${sanitizeText(item?.content, 500)}`)
        .filter(Boolean)
        .join('\n')
    : '';

  const prompt = [
    `Mode: ${mode}`,
    existingSummary ? `Existing summary:\n${existingSummary}` : '',
    compactLogs ? `Recent logs:\n${compactLogs}` : '',
    incomingMessage ? `Latest incoming user prompt:\n${sanitizeText(incomingMessage, 1_000)}` : '',
    recentContext ? `Latest chat context:\n${recentContext}` : '',
  ]
    .filter(Boolean)
    .join('\n\n')
    .slice(0, MAX_SUMMARY_PROMPT_CHARS);

  if (!prompt) return '';

  try {
    const summary = await runTextModel({
      apiKey,
      systemPrompt: sanitizeText(
        env?.SUMMARY_ANALYZER_SYSTEM_PROMPT ?? SUMMARY_ANALYZER_PROMPT,
        4_000,
      ),
      userPrompt: prompt,
      temperature: 0.2,
      maxTokens: 900,
    });
    return sanitizeText(summary, 8_000);
  } catch {
    return '';
  }
}

async function fetchRecentModeLogs(mode, idToken) {
  const node = `logs/${mode}`;
  const url = new URL(`${FIREBASE_DATABASE_URL}/${node}.json`);
  url.searchParams.set('auth', idToken);
  url.searchParams.set('orderBy', JSON.stringify('timestamp'));
  url.searchParams.set('limitToLast', String(MAX_LOG_SCAN));
  const data = await fetchWithTimeoutJson(url.toString(), WIKI_FETCH_TIMEOUT_MS);
  if (!data || typeof data !== 'object') return [];
  return Object.values(data)
    .filter(Boolean)
    .sort((a, b) => Number(a?.timestamp ?? 0) - Number(b?.timestamp ?? 0));
}

function buildLogPayload({ request, message, taggedMessage, reply, chatHistory, imageCount }) {
  return {
    timestamp: Date.now(),
    userAgent: sanitizeText(request?.headers?.get('user-agent'), 240),
    request: {
      prompt: sanitizeText(taggedMessage || message, 8_000),
      imageCount: Number.isFinite(imageCount) ? imageCount : 0,
      chatHistorySize: Array.isArray(chatHistory) ? chatHistory.length : 0,
    },
    response: {
      text: sanitizeText(reply, 12_000),
      model: TEXT_MODEL,
    },
    anonymized: true,
  };
}

async function logConversationEvent({ firebaseSession, mode, payload }) {
  if (!firebaseSession?.idToken) return;
  const path = `logs/${mode}`;
  await firebasePush(path, payload, firebaseSession.idToken);
}

async function firebaseRead(path, idToken) {
  try {
    const url = `${FIREBASE_DATABASE_URL}/${path}.json?auth=${encodeURIComponent(idToken)}`;
    const response = await fetchWithTimeout(url, {
      method: 'GET',
      keepalive: true,
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return null;
    return await safeJson(response);
  } catch {
    return null;
  }
}

async function firebasePatch(path, value, idToken) {
  try {
    await firebaseWrite(path, 'PATCH', value, idToken);
  } catch {}
}

async function firebasePush(path, value, idToken) {
  try {
    await firebaseWrite(path, 'POST', value, idToken);
  } catch {}
}

async function firebaseWrite(path, method, value, idToken) {
  const url = `${FIREBASE_DATABASE_URL}/${path}.json?auth=${encodeURIComponent(idToken)}`;
  await withRetry(async () =>
    fetchWithTimeout(url, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(value ?? {}),
      keepalive: true,
    }),
  );
}

function runInBackground(promise, waitUntil) {
  if (!promise) return;
  if (typeof waitUntil === 'function') {
    waitUntil(promise.catch(() => {}));
    return;
  }
  promise.catch(() => {});
}

async function withRetry(fn, retries = 2) {
  let lastError = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      const response = await fn();
      if (!response?.ok && attempt < retries) continue;
      return response;
    } catch (error) {
      lastError = error;
      if (attempt < retries) continue;
      throw error;
    }
  }
  if (lastError) throw lastError;
  return null;
}

async function fetchWithTimeout(url, init = {}, timeoutMs = FIREBASE_TIMEOUT_MS) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('timeout'), timeoutMs);
  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

function extractDeltaFromEvent(rawEvent) {
  const lines = rawEvent.split('\n');
  let payload = '';

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line.startsWith('data:')) continue;
    const dataPart = line.slice(5).trim();
    if (!dataPart || dataPart === '[DONE]') continue;
    payload += dataPart;
  }

  if (!payload) return '';

  try {
    const event = JSON.parse(payload);
    return extractDelta(event);
  } catch {
    return '';
  }
}

function extractDelta(data) {
  const delta = data?.choices?.[0]?.delta?.content;
  if (typeof delta === 'string') return delta;
  if (Array.isArray(delta)) {
    return delta.map((part) => (typeof part?.text === 'string' ? part.text : '')).join('');
  }
  return '';
}

function extractTextContent(data) {
  const choice = data?.choices?.[0];
  const messageContent = choice?.message?.content;

  if (typeof messageContent === 'string') {
    return messageContent;
  }

  if (Array.isArray(messageContent)) {
    return messageContent
      .map((part) => (typeof part?.text === 'string' ? part.text : ''))
      .join('')
      .trim();
  }

  return '';
}

function sanitizeText(value, maxChars) {
  return String(value ?? '')
    .replace(/\u0000/g, '')
    .trim()
    .slice(0, maxChars);
}

function sanitizeImageUrl(value) {
  const url = String(value ?? '').trim().slice(0, MAX_IMAGE_URL_CHARS);
  if (!url) return '';

  if (url.startsWith('data:image/')) return url;
  if (url.startsWith('https://') || url.startsWith('http://')) return url;
  return '';
}

function sanitizeImageUrls(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeImageUrl(entry)).filter(Boolean).slice(0, 3);
  }
  const single = sanitizeImageUrl(value);
  return single ? [single] : [];
}

async function summarizeWithVisionModel({ imageUrl, apiKey }) {
  const payload = {
    model: VISION_MODEL,
    stream: false,
    temperature: 0.2,
    messages: [
      {
        role: 'user',
        content: [
          { type: 'text', text: VISION_PROMPT },
          { type: 'image_url', image_url: { url: imageUrl } },
        ],
      },
    ],
  };

  const response = await fetch(NVIDIA_CHAT_COMPLETIONS_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
    keepalive: true,
  });

  if (!response.ok) {
    return '';
  }

  const data = await safeJson(response);
  return sanitizeText(extractTextContent(data), 4_000);
}

async function safeJson(response) {
  const contentType = response.headers.get('content-type') ?? '';
  try {
    if (contentType.includes('application/json')) {
      return await response.json();
    }
    const text = await response.text();
    return text ? { raw: text } : null;
  } catch {
    return null;
  }
}

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
    },
  });
}

function withCors(response, request, env) {
  const headers = new Headers(response.headers);
  const cors = corsHeaders(request, env);
  for (const [key, value] of Object.entries(cors)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function corsHeaders(request, env) {
  const configured = String(env?.CORS_ALLOW_ORIGIN ?? '*').trim() || '*';
  const requestOrigin = request?.headers?.get('origin') ?? '';
  const allowOrigin = configured === '*' ? '*' : configured === requestOrigin ? configured : 'null';

  return {
    'access-control-allow-origin': allowOrigin,
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'Content-Type, Authorization',
    vary: 'Origin',
  };
}
