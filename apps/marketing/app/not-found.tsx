import Link from "next/link";

export default function NotFound() {
  return (
    <main className="flex min-h-screen flex-col items-center justify-center gap-4">
      <h1 className="text-3xl font-bold">404</h1>
      <Link href="/" className="text-amber-400">
        Go home
      </Link>
    </main>
  );
}
