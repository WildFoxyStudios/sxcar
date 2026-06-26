import { site } from "@/lib/site";
import { StoreButtons } from "./StoreButtons";

export function Hero() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-20 text-center">
      <p className="mb-3 text-sm font-medium uppercase tracking-widest text-amber-400">18+ · LGBTQ+</p>
      <h1 className="mx-auto max-w-3xl text-4xl font-extrabold tracking-tight sm:text-6xl">{site.tagline}</h1>
      <p className="mx-auto mt-6 max-w-2xl text-lg text-neutral-300">{site.description}</p>
      <div className="mt-8 flex justify-center"><StoreButtons /></div>
    </section>
  );
}
