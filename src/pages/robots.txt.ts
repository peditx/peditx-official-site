/* robots.txt. Served from src/ so nothing under public/ has to change — that
   directory belongs to the site. Disallow /admin/ so the panel stays out of
   the index. */
const body = [
  'User-agent: *',
  'Allow: /',
  'Disallow: /admin/',
  '',
  'Sitemap: https://codes.peditx.ir/sitemap.xml',
  '',
].join('\n');

export function GET() {
  return new Response(body, {
    headers: { 'Content-Type': 'text/plain; charset=utf-8' },
  });
}
