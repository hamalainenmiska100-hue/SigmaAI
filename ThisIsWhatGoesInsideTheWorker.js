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
 *   CORS_ALLOW_ORIGIN (default: *)
 */

const NVIDIA_CHAT_COMPLETIONS_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const GEMINI_SUMMARY_URL = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent';
const MODEL = 'mistralai/devstral-2-123b-instruct-2512';
const IMAGE_SUMMARY_PROMPT = 'analyze this image and give me an detailed summary of it';

const MAX_MESSAGE_CHARS = 16_000;
const MAX_HISTORY_ITEMS = 40;
const MAX_IMAGE_URL_CHARS = 2_000_000;
const UPSTREAM_TIMEOUT_MS = 55_000;
const GEMINI_TIMEOUT_MS = 20_000;
const MAX_GEMINI_IMAGE_BYTES = 5 * 1024 * 1024;

export async function onRequestPost(context) {
  return handleChatRequest(context.request, context.env);
}

export async function onRequestOptions(context) {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(context?.request, context?.env),
  });
}

export default {
  async fetch(request, env) {
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

    return handleChatRequest(request, env);
  },
};

async function handleChatRequest(request, env) {
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
  const imageData = sanitizeImageUrl(payload?.imageData);
  const languageTag = sanitizeText(payload?.languageTag, 32);
  const systemMode = sanitizeText(payload?.systemMode, 32).toLowerCase();
  const selectedInstruction = pickSystemInstruction(env, systemMode);
  const chatHistory = Array.isArray(payload?.chatHistory) ? payload.chatHistory.slice(-MAX_HISTORY_ITEMS) : [];
  const stream = payload?.stream !== false;

  if (!message && !imageData) {
    return withCors(json({ error: 'Message or image is required' }, 400), request, env);
  }

  const apiKey = String(env?.NVIDIA_API_KEY ?? env?.NIM_API_KEY ?? '').trim();
  if (!apiKey) {
    return withCors(json({ error: 'Server misconfigured: missing NVIDIA_API_KEY' }, 500), request, env);
  }
  const geminiApiKey = String(env?.AISTUDIO_API_KEY ?? '').trim();
  const imageSummaryCache = new Map();

  const messages = [];
  if (selectedInstruction) messages.push({ role: 'system', content: selectedInstruction });

  for (const item of chatHistory) {
    const role = item?.role === 'assistant' ? 'assistant' : 'user';
    const content = sanitizeText(item?.content, MAX_MESSAGE_CHARS);
    const itemImage = sanitizeImageUrl(item?.imageData);
    if (!content && !itemImage) continue;

    if (itemImage && role === 'user') {
      const imageSummary = await summarizeImageForNvidia({
        imageUrl: itemImage,
        geminiApiKey,
        cache: imageSummaryCache,
      });
      const combinedText = [content, imageSummary ? `Image summary:\n${imageSummary}` : '']
        .filter(Boolean)
        .join('\n\n')
        .trim();
      messages.push({ role, content: combinedText || content || 'Image shared by user.' });
    } else {
      messages.push({ role, content });
    }
  }

  if (imageData) {
    const imageSummary = await summarizeImageForNvidia({
      imageUrl: imageData,
      geminiApiKey,
      cache: imageSummaryCache,
    });
    const taggedMessage = [message, languageTag].filter(Boolean).join(' ').trim();
    const combinedText = [taggedMessage, imageSummary ? `Image summary:\n${imageSummary}` : '']
      .filter(Boolean)
      .join('\n\n')
      .trim();
    messages.push({
      role: 'user',
      content: combinedText || taggedMessage || 'Image shared by user.',
    });
  } else {
    const taggedMessage = [message, languageTag].filter(Boolean).join(' ').trim();
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
        model: MODEL,
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
    return withCors(json({ type: 'message', content }), request, env);
  }

  if (!upstreamResponse.ok || !upstreamResponse.body) {
    clearTimeout(timeout);
    const details = await safeJson(upstreamResponse);
    return withCors(json({ error: 'Upstream provider error', details }, 502), request, env);
  }

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

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

async function summarizeImageForNvidia({ imageUrl, geminiApiKey, cache }) {
  if (!imageUrl) return '';
  if (cache?.has(imageUrl)) return cache.get(imageUrl) ?? '';
  if (!geminiApiKey) {
    cache?.set(imageUrl, '');
    return '';
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort('gemini-timeout'), GEMINI_TIMEOUT_MS);

  try {
    const imagePart = await buildGeminiImagePart(imageUrl, controller.signal);
    if (!imagePart) {
      cache?.set(imageUrl, '');
      return '';
    }

    const response = await fetch(`${GEMINI_SUMMARY_URL}?key=${encodeURIComponent(geminiApiKey)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        contents: [
          {
            role: 'user',
            parts: [
              { text: IMAGE_SUMMARY_PROMPT },
              imagePart,
            ],
          },
        ],
      }),
      signal: controller.signal,
      keepalive: true,
    });

    if (!response.ok) {
      cache?.set(imageUrl, '');
      return '';
    }

    const data = await safeJson(response);
    const text = extractGeminiText(data);
    cache?.set(imageUrl, text);
    return text;
  } catch {
    cache?.set(imageUrl, '');
    return '';
  } finally {
    clearTimeout(timeout);
  }
}

async function buildGeminiImagePart(imageUrl, signal) {
  if (imageUrl.startsWith('data:image/')) {
    const match = /^data:(image\/[a-zA-Z0-9+.-]+);base64,(.+)$/s.exec(imageUrl);
    if (!match) return null;
    return {
      inlineData: {
        mimeType: match[1],
        data: match[2],
      },
    };
  }

  if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
    return null;
  }

  const imageResponse = await fetch(imageUrl, {
    method: 'GET',
    signal,
    keepalive: true,
  });
  if (!imageResponse.ok) return null;

  const mimeType = sanitizeText(imageResponse.headers.get('content-type') ?? 'image/jpeg', 120).split(';')[0] || 'image/jpeg';
  if (!mimeType.startsWith('image/')) return null;

  const bytes = new Uint8Array(await imageResponse.arrayBuffer());
  if (!bytes.length || bytes.length > MAX_GEMINI_IMAGE_BYTES) return null;

  return {
    inlineData: {
      mimeType,
      data: uint8ToBase64(bytes),
    },
  };
}

function uint8ToBase64(bytes) {
  let binary = '';
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.subarray(i, i + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary);
}

function extractGeminiText(data) {
  const parts = data?.candidates?.[0]?.content?.parts;
  if (!Array.isArray(parts)) return '';
  return parts
    .map((part) => (typeof part?.text === 'string' ? part.text : ''))
    .join('')
    .trim();
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
