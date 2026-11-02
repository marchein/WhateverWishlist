import bcrypt from 'bcryptjs';
import { randomUUID } from 'node:crypto';
import { Router } from 'express';
import { requireAuth, signToken } from '../auth.js';
import type { DB } from '../db.js';
import { HttpError } from '../errors.js';
import { now, toUserDto, type UserRow } from '../models.js';
import { loginSchema, registerSchema } from '../validation.js';

// Compared against when the user does not exist, so response time doesn't reveal registered emails.
const DUMMY_HASH = bcrypt.hashSync('dummy-password-for-timing', 12);

export function authRouter(db: DB): Router {
  const router = Router();

  router.post('/register', async (req, res) => {
    const input = registerSchema.parse(req.body);
    const exists = db.prepare('SELECT 1 FROM users WHERE email = ?').get(input.email);
    if (exists) throw new HttpError(409, 'EMAIL_TAKEN', 'An account with this email already exists');

    const user: UserRow = {
      id: randomUUID(),
      email: input.email,
      display_name: input.displayName,
      password_hash: await bcrypt.hash(input.password, 12),
      session_version: 0,
      created_at: now(),
    };
    db.prepare(
      `INSERT INTO users (id, email, display_name, password_hash, created_at)
       VALUES (@id, @email, @display_name, @password_hash, @created_at)`,
    ).run(user);

    res.status(201).json({ token: signToken(user.id), user: toUserDto(user) });
  });

  router.post('/login', async (req, res) => {
    const input = loginSchema.parse(req.body);
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(input.email) as UserRow | undefined;
    const valid = await bcrypt.compare(input.password, user?.password_hash ?? DUMMY_HASH);
    if (!user || !valid) throw new HttpError(401, 'INVALID_CREDENTIALS', 'Invalid email or password');

    res.json({ token: signToken(user.id, user.session_version), user: toUserDto(user) });
  });

  router.get('/me', requireAuth(db), (req, res) => {
    const user = req.user!;
    res.json({ id: user.id, email: user.email, displayName: user.displayName });
  });

  return router;
}
