import { z } from 'zod';

export const UPLOAD_PATH_RE = /^\/uploads\/[a-f0-9-]{36}\.(jpg|png|gif|webp)$/;

export function isHttpUrl(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === 'http:' || url.protocol === 'https:';
  } catch {
    return false;
  }
}

const httpUrl = z.string().trim().max(2048).refine(isHttpUrl, 'Must be an http(s) URL');
const optionalText = (max: number) =>
  z
    .string()
    .trim()
    .max(max)
    .nullish()
    .transform((value) => value || null);

export const passwordSchema = z.string()
  .min(8, 'Password must be at least 8 characters')
  .refine((value) => Buffer.byteLength(value) <= 72, 'Password is too long');

export const registerSchema = z.object({
  email: z.string().trim().toLowerCase().pipe(z.email()),
  password: passwordSchema,
  displayName: z.string().trim().min(1).max(60),
});

export const loginSchema = z.object({
  email: z.string().trim().toLowerCase(),
  password: z.string().max(200),
});

const wishlistFields = {
  title: z.string().trim().min(1).max(120),
  description: optionalText(1000),
  eventDate: z.iso.date().nullish().transform((value) => value ?? null),
};

export const createWishlistSchema = z.object(wishlistFields);
export const updateWishlistSchema = z.object(wishlistFields).partial();

// Old clients send no body: they don't know about followers, so the safe default is to remove them.
export const regenerateShareTokenSchema = z.object({ keepFollowers: z.boolean().default(false) });

const itemFields = {
  title: z.string().trim().min(1).max(300),
  notes: optionalText(2000),
  imageUrl: z
    .string()
    .trim()
    .max(2048)
    .refine((value) => isHttpUrl(value) || UPLOAD_PATH_RE.test(value), 'Must be an http(s) URL or an uploaded image')
    .nullish()
    .transform((value) => value || null),
  price: z
    .number()
    .nonnegative()
    .max(1_000_000_000)
    .nullish()
    .transform((value) => (value == null ? null : Math.round(value * 100) / 100)),
  currency: z
    .string()
    .trim()
    .toUpperCase()
    .regex(/^[A-Z]{3}$/, 'Must be a 3-letter currency code')
    .nullish()
    .transform((value) => value ?? null),
  priority: z.number().int().min(1).max(5),
  quantity: z.number().int().min(1).max(999),
  links: z.array(httpUrl).max(20),
};

export const createItemSchema = z.object({
  ...itemFields,
  priority: itemFields.priority.default(3),
  quantity: itemFields.quantity.default(1),
  links: itemFields.links.default([]),
});
export const updateItemSchema = z.object(itemFields).partial();

export const purchaseSchema = z.object({
  name: z.string().trim().max(60).optional(),
  quantity: z.number().int().min(1).max(999).default(1),
});

export const revertSchema = z.object({
  name: z.string().trim().max(60).optional(),
});

export const scrapeSchema = z.object({
  input: z.string().trim().min(1).max(4000),
});
