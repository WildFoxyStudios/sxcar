import Link from "next/link";
import { site } from "@/lib/site";

export function SiteHeader() {
  return (
    <header className="mx-auto flex max-w-6xl items-center justify-between p-6">
      <Link href="/" className="text-lg font-bold">{site.name}</Link>
      <nav className="flex gap-6 text-sm text-neutral-300">
        <Link href="/support">Support</Link>
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
      </nav>
    </header>
  );
}
