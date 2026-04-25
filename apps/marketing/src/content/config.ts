// Audit Ch10-W093, W105: blog metadata lives in a content collection so the
// listing page (`/blog`) and the per-post pages (`/blog/<slug>`) cannot drift.
// Each entry's filename IS the slug — adding a new post means dropping a new
// frontmatter file under `src/content/blog/<slug>.md` AND a matching Astro
// page at `src/pages/blog/<slug>.astro`. The collection enforces that the
// metadata is present and well-typed.
import { defineCollection, z } from 'astro:content';

const blog = defineCollection({
  type: 'data',
  schema: z.object({
    title: z.string().min(1),
    excerpt: z.string().min(1),
    date: z.coerce.date(),
    category: z.string().min(1),
    image: z.string().min(1),
    readTimeMinutes: z.number().int().positive().optional(),
  }),
});

export const collections = { blog };
