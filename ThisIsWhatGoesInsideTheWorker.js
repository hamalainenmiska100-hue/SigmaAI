/**
 * Cloudflare Pages Function / Worker proxy for SigmaAI.
 *
 * Route expected by Flutter app:
 *   POST https://<your-domain>/chat
 *
 * Required env var:
 *   NVIDIA_API_KEY (or NIM_API_KEY)
 */

const NVIDIA_CHAT_COMPLETIONS_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';
const MODEL = 'stepfun-ai/step-3.5-flash';

export async function onRequestPost(context) {
  return handleChatRequest(context.request, context.env);
}

export async function onRequestOptions() {
  return new Response(null, {
    status: 204,
    headers: corsHeaders(),
  });
}

// Also support classic module Workers entrypoint (`export default { fetch() { ... } }`),
// so this file works in either Cloudflare Pages Functions or Cloudflare Workers.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(),
      });
    }

    if (url.pathname !== '/chat') {
      return withCors(
        json(
          {
            error: 'Not found',
          },
          404,
        ),
      );
    }

    if (request.method !== 'POST') {
      return withCors(
        json(
          {
            error: 'Method not allowed',
          },
          405,
        ),
      );
    }

    return handleChatRequest(request, env);
  },
};

async function handleChatRequest(request, env) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return withCors(json({ error: 'Invalid JSON' }, 400));
  }

  const message = String(payload?.message ?? '').trim();
  const customInstructions = String(payload?.customInstructions ?? '').trim();
  const chatHistory = Array.isArray(payload?.chatHistory) ? payload.chatHistory : [];

  if (!message) {
    return withCors(json({ error: 'Message is required' }, 400));
  }

  const apiKey = String(env?.NVIDIA_API_KEY ?? env?.NIM_API_KEY ?? '').trim();
  if (!apiKey) {
    return withCors(json({ error: 'Server misconfigured: missing NVIDIA_API_KEY' }, 500));
  }

  const messages = [];

  if (customInstructions) {
    messages.push({ role: 'system', content: customInstructions });
  }

  for (const item of chatHistory) {
    const role = item?.role === 'assistant' ? 'assistant' : item?.role === 'system' ? 'system' : 'user';
    const content = String(item?.content ?? '').trim();
    if (!content) {
      continue;
    }
    messages.push({ role, content });
  }

  messages.push({ role: 'user', content: message });

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
        stream: false,
        temperature: 0.2,
        // Turn off visible reasoning/thinking for models that support this template flag.
        extra_body: {
          chat_template_kwargs: {
            thinking: false,
          },
        },
      }),
    });
  } catch {
    return withCors(json({ error: 'Upstream provider unreachable' }, 502));
  }

  if (upstreamResponse.status === 429) {
    return withCors(json({ error: 'Rate limit' }, 429));
  }

  if (!upstreamResponse.ok) {
    const details = await safeJson(upstreamResponse);
    return withCors(json({ error: 'Upstream provider error', details }, 502));
  }

  const data = await safeJson(upstreamResponse);
  const content = extractTextContent(data);

  if (!content) {
    return withCors(json({ error: 'Empty response from upstream provider' }, 502));
  }

  return withCors(
    json({
      type: 'message',
      content,
    }),
  );
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

function withCors(response) {
  const headers = new Headers(response.headers);
  const cors = corsHeaders();
  for (const [key, value] of Object.entries(cors)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

function corsHeaders() {
  return {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'POST, OPTIONS',
    'access-control-allow-headers': 'Content-Type, Authorization',
  };
}
