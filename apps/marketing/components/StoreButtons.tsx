import { site } from "@/lib/site";

export function StoreButtons() {
  return (
    <div className="flex flex-wrap gap-3">
      <a href={site.stores.appStore} className="rounded-xl bg-white px-5 py-3 font-semibold text-neutral-950">App Store</a>
      <a href={site.stores.googlePlay} className="rounded-xl border border-neutral-700 px-5 py-3 font-semibold">Google Play</a>
    </div>
  );
}
