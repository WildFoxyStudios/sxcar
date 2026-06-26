import Link from "next/link";
import { site } from "@/lib/site";

export function SiteFooter() {
  return (
    <footer className="mx-auto max-w-6xl border-t border-neutral-800 p-6 text-sm text-neutral-400">
      <p>© {site.name}. 18+ only.</p>
      <nav className="mt-2 flex gap-4">
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/support">Support</Link>
        <Link href="/blog">Blog</Link>
      </nav>
    </footer>
  );
}
