import jwt from 'jsonwebtoken';
import crypto from 'crypto';

const JWT_SECRET = process.env.JWT_SECRET || (console.warn('[auth] JWT_SECRET não definido — usando fallback volátil (sessões invalidadas no restart)'), crypto.randomUUID());

export function signToken(user) {
  return jwt.sign(
    { id: user.id, nome: user.nome, email: user.email, nivel: user.nivel },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
}

export function verifyToken(token) {
  return jwt.verify(token, JWT_SECRET);
}

export async function authenticate(request, reply) {
  const auth = request.headers.authorization;
  if (!auth || !auth.startsWith('Bearer ')) {
    return reply.code(401).send({ error: 'Token não fornecido' });
  }
  try {
    request.user = verifyToken(auth.slice(7));
  } catch {
    return reply.code(401).send({ error: 'Token inválido ou expirado' });
  }
}

export async function requireAdmin(request, reply) {
  if (!request.user || request.user.nivel !== 'admin') {
    return reply.code(403).send({ error: 'Acesso restrito a administradores' });
  }
}
