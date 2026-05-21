import fetch from 'node-fetch';
import crypto from 'crypto';

const EXTERNAL_API = process.env.EXTERNAL_API || 'https://api.projetosdinamicos.com.br/leilao-commodities';
const API_TOKEN = process.env.API_TOKEN || crypto.randomUUID();

export async function apiRequest(action, body = {}) {
  const res = await fetch(`${EXTERNAL_API}/api/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${API_TOKEN}` },
    body: JSON.stringify({ project: 'leilao-commodities', ...body }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: 'API request failed' }));
    throw new Error(err.error || `HTTP ${res.status}`);
  }
  return res.json();
}
