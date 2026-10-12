/* Sitemap. Build-time only, no new dependency.
   The site is one page plus any standalone page the panel drops into
   public/<path>/index.html, so those are scanned from disk — a new page is
   indexed on the next build without anyone touching this file. */
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const site = 'https://codes.peditx.ir';

/* A directory counts as a page only when it carries an index.html, which is
   exactly what the panel writes. /admin/ is disallowed in robots.txt, so it
   stays out here too; asset folders (fonts, uploads…) never match. */
const pages = readdirSync(join(process.cwd(), 'public'), { withFileTypes: true })
  .filter((d) => d.isDirectory() && !d.name.startsWith('_') && d.name !== 'admin')
  .filter((d) => existsSync(join(process.cwd(), 'public', d.name, 'index.html')))
  .map((d) => '/' + d.name + '/')
  .sort();

const xml =
  `<?xml version="1.0" encoding="UTF-8"?>\n` +
  `<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n` +
  ['/', ...pages]
    .map((loc) => `  <url><loc>${site}${loc}</loc></url>`)
    .join('\n') +
  `\n</urlset>\n`;

export function GET() {
  return new Response(xml, {
    headers: { 'Content-Type': 'application/xml; charset=utf-8' },
  });
}
