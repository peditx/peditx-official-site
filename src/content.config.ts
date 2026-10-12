import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

/* Content collections. Every field a search engine should read is rendered at
   build time — the browser never fills any of this in. Keep the frontmatter
   keys in sync with src/content/index.ts, which is the single place the
   Persian interface text lives. */

const projects = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/projects' }),
  schema: z.object({
    name: z.string(),
    description: z.string(),
    iconUrl: z.string().url().optional(),
    url: z.string().url(),
  }),
});

const links = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/links' }),
  schema: z.object({
    name: z.string(),
    url: z.string().url(),
    /* Raw SVG markup, kept editable in frontmatter. Sanitised at render time. */
    icon: z.string(),
    /* Brand marks (YouTube, X, Spotify…) are solid shapes and read as empty
       boxes if they are stroked; outline marks (GitHub, Instagram) are the
       opposite. One rule for both made every logo look wrong. */
    solid: z.boolean().default(false),
  }),
});

const videos = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/videos' }),
  schema: z.object({
    title: z.string(),
    videoId: z.string().regex(/^[\w-]{11}$/),
    thumbnailUrl: z.string().url().optional(),
  }),
});

const blog = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(),
    pubDate: z.coerce.date(),
    description: z.string(),
    author: z.string().default('PeDitX'),
  }),
});

export const collections = { projects, links, videos, blog };
