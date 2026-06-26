import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  typescript: {
    // Narrow workaround for a Next.js 16 bug in its OWN generated file
    // `.next/types/validator.ts` (TS2709: "Cannot use namespace
    // 'ResolvingMetadata'/'ResolvingViewport' as a type"). It regenerates on
    // every build, so it can't be patched. This only silences `next build`'s
    // type gate. Real type-checking of OUR code is restored via
    // `npm run typecheck` (tsc against tsconfig.typecheck.json, which excludes
    // only that generated file) — run it in CI so app-code type errors fail.
    ignoreBuildErrors: true,
  },
};

export default nextConfig;
