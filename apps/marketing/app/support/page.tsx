import { buildMetadata, faqJsonLd } from "@/lib/seo";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";

export const metadata = buildMetadata({ title: "Support", path: "/support" });

const faqs = [
  { q: "How do I create an account?", a: "Download the app, sign up with email or Apple/Google, and verify you're 18+." },
  { q: "How do I stay safe?", a: "Use distance hiding, incognito, blocking and reporting. We moderate content and respond to reports." },
  { q: "How do I delete my account?", a: "Settings → Account → Delete account. Your data is erased per our privacy policy." },
];

export default function Support() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-4xl font-bold">Support</h1>
        <div className="mt-8 space-y-6">
          {faqs.map((f) => (
            <div key={f.q}>
              <h2 className="text-xl font-semibold">{f.q}</h2>
              <p className="mt-2 text-neutral-300">{f.a}</p>
            </div>
          ))}
        </div>
      </main>
      <SiteFooter />
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(faqJsonLd(faqs)) }} />
    </>
  );
}
