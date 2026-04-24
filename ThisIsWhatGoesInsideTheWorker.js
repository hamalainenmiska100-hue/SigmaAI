/**
 * Cloudflare Pages Function / Worker example for SigmaAI proxy route.
 *
 * Route expected by Flutter app:
 *   POST https://<your-domain>/chat
 *
 * Deploy notes:
 * - For Cloudflare Pages Functions, place this handler under functions/chat.js.
 * - For a standalone Worker, export default with fetch(request, env).
 */

export async function onRequestPost(context) {
  const { request, env } = context;

  let payload;
  try {
    payload = await request.json();
  } catch {
    return json({ error: 'Invalid JSON' }, 400);
  }

  const message = String(payload?.message ?? '').trim();
  const customInstructions = String(payload?.customInstructions ?? '').trim();
  const chatHistory = Array.isArray(payload?.chatHistory) ? payload.chatHistory : [];

  if (!message) {
    return json({ error: 'Message is required' }, 400);
  }

  // Replace this section with your upstream provider call.
  // Keep secrets in Cloudflare environment variables, never in Flutter code.
  // Example response contract returned back to app:
  return json({
    type: 'message',
    content: `You said: ${message}\n\nCustom instructions length: ${customInstructions.length}\nHistory items: ${chatHistory.length}`,
  });
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
