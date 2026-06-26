import { buildMetadata } from "@/lib/seo";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";

export const metadata = buildMetadata({ title: "Terms of Service", path: "/terms" });

export default function Terms() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-4xl font-bold">Terms of Service</h1>
        <p className="mt-4 text-neutral-300">By using proyecto-X, you agree to these terms and our privacy policy. We are committed to a safe, respectful community for adults (18+).</p>
        <h2 className="mt-8 text-2xl font-semibold">Eligibility</h2>
        <p className="mt-2 text-neutral-300">You must be at least 18 years old and legally able to enter into binding agreements. Age verification is required.</p>
        <h2 className="mt-8 text-2xl font-semibold">Conduct</h2>
        <p className="mt-2 text-neutral-300">You agree not to harass, abuse, or post illegal content. Violations may result in account termination and legal action.</p>
        <h2 className="mt-8 text-2xl font-semibold">Termination</h2>
        <p className="mt-2 text-neutral-300">We may suspend or terminate your account at any time for violations. You may delete your account anytime in Settings.</p>
        <h2 className="mt-8 text-2xl font-semibold">Governing Law</h2>
        <p className="mt-2 text-neutral-300">These terms are governed by applicable law. Disputes are resolved according to applicable jurisdiction.</p>
      </main>
      <SiteFooter />
    </>
  );
}
