# proyecto-X — marketing (Next.js)

Sitio público de marketing (SEO) en Next.js App Router. Separado de la app de producto (que va `noindex`).

## Desarrollo
- `npm install`
- `npm run dev` (http://localhost:3000)
- `npm run build` · `npm test` · `npm run lint`

## SEO
- Metadata API por página (title/description/canonical/OpenGraph/Twitter) vía `lib/seo.ts` (`buildMetadata`).
- JSON-LD: Organization, WebSite, SoftwareApplication (landing) y FAQPage (support).
- `sitemap.xml` (`app/sitemap.ts`) y `robots.txt` (`app/robots.ts`).
- OG image **dinámica** generada en build con `next/og` en `app/opengraph-image.tsx` (sin binarios; la convención de archivo sobreescribe cualquier `images` del metadata).

## Despliegue
- Vercel (cuando se conecte la cuenta): `vercel` / `vercel --prod`.
