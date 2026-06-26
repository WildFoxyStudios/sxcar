import { buildMetadata } from "@/lib/seo";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";

export const metadata = buildMetadata({ title: "Blog", path: "/blog" });

export default function Blog() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-4xl font-bold">Blog</h1>
        <p className="mt-4 text-neutral-300">Coming soon — guides on safety, dating, and community.</p>
      </main>
      <SiteFooter />
    </>
  );
}
