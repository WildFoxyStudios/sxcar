import { buildMetadata } from "@/lib/seo";
import { SiteHeader } from "@/components/SiteHeader";
import { SiteFooter } from "@/components/SiteFooter";

export const metadata = buildMetadata({ title: "Privacy Policy", path: "/privacy" });

export default function Privacy() {
  return (
    <>
      <SiteHeader />
      <main className="mx-auto max-w-3xl px-6 py-16">
        <h1 className="text-4xl font-bold">Privacy Policy</h1>
        <p className="mt-4 text-neutral-300">We collect the minimum data needed to run the service and protect a vulnerable community. This summary covers what we collect, why, and your rights (GDPR/CCPA).</p>
        <h2 className="mt-8 text-2xl font-semibold">Data we collect</h2>
        <p className="mt-2 text-neutral-300">Account (email, age verification), profile, approximate location (with controls), messages, and device/push tokens.</p>
        <h2 className="mt-8 text-2xl font-semibold">Your rights</h2>
        <p className="mt-2 text-neutral-300">Access, export, and deletion (right to be forgotten). Contact privacy@proyecto-x.example.</p>
      </main>
      <SiteFooter />
    </>
  );
}
