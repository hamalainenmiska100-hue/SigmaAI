/**
 * Cloudflare Pages Function / Worker proxy for Sigma.
 *
 * Route expected by Flutter app:
 *   POST https://<your-domain>/chat
 *
 * Required secret env var:
 *   NVIDIA_API_KEY (or NIM_API_KEY)
 *
 * Optional plain text env var:
 *   SYSTEM_INSTRUCTION
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
      return withCors(json({ error: 'Not found' }, 404));
    }

    if (request.method !== 'POST') {
      return withCors(json({ error: 'Method not allowed' }, 405));
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
  const imageData = String(payload?.imageData ?? '').trim();
  const customInstructions = String(payload?.customInstructions ?? '').trim();
  const systemInstruction = String(env?.SYSTEM_INSTRUCTION ?? '').trim();
  const chatHistory = Array.isArray(payload?.chatHistory) ? payload.chatHistory : [];
  const stream = payload?.stream !== false;

  if (!message && !imageData) {
    return withCors(json({ error: 'Message or image is required' }, 400));
  }

  const apiKey = String(env?.NVIDIA_API_KEY ?? env?.NIM_API_KEY ?? '').trim();
  if (!apiKey) {
    return withCors(json({ error: 'Server misconfigured: missing NVIDIA_API_KEY' }, 500));
  }

  const messages = [];
  if (systemInstruction) messages.push({ role: 'system', content: systemInstruction });
  if (customInstructions) messages.push({ role: 'system', content: customInstructions });

  for (const item of chatHistory) {
    const role = item?.role === 'assistant' ? 'assistant' : item?.role === 'system' ? 'system' : 'user';
    const content = String(item?.content ?? '').trim();
    const itemImage = String(item?.imageData ?? '').trim();
    if (!content && !itemImage) continue;

    if (itemImage && role === 'user') {
      messages.push({
        role,
        content: [
          ...(content ? [{ type: 'text', text: content }] : []),
          { type: 'image_url', image_url: { url: itemImage } },
        ],
      });
    } else {
      messages.push({ role, content });
    }
  }

  if (imageData) {
    messages.push({
      role: 'user',
      content: [
        ...(message ? [{ type: 'text', text: message }] : []),
        { type: 'image_url', image_url: { url: imageData } },
      ],
    });
  } else {
    messages.push({ role: 'user', content: message });
  }

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

  if (!stream) {
    const data = await safeJson(upstreamResponse);
    const content = extractTextContent(data);
    return withCors(json({ type: 'message', content }));
  }

  if (!upstreamResponse.ok || !upstreamResponse.body) {
    const details = await safeJson(upstreamResponse);
    return withCors(json({ error: 'Upstream provider error', details }, 502));
  }

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  const transformed = new ReadableStream({
    async start(controller) {
      let buffer = '';
      const reader = upstreamResponse.body.getReader();
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });

        const segments = buffer.split('\n');
        buffer = segments.pop() ?? '';

        for (const rawLine of segments) {
          const line = rawLine.trim();
          if (!line.startsWith('data:')) continue;
          const payload = line.slice(5).trim();
          if (!payload || payload === '[DONE]') continue;

          let event;
          try {
            event = JSON.parse(payload);
          } catch {
            continue;
          }

          const delta = extractDelta(event);
          if (!delta) continue;
          controller.enqueue(encoder.encode(`data: ${JSON.stringify({ type: 'delta', delta })}\n\n`));
        }
      }

      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(transformed, {
    status: 200,
    headers: {
      ...corsHeaders(),
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-store',
      connection: 'keep-alive',
    },
  });
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
