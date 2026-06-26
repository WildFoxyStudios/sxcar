const features = [
  { title: "Live grid", body: "See guys near you, sorted by distance, online now." },
  { title: "Chat", body: "Message, send photos, share your location — in real time." },
  { title: "Private albums", body: "Share private photos with people you choose, and unshare anytime." },
  { title: "Privacy & safety", body: "Hide your distance, go incognito, and stay in control." },
];

export function FeatureGrid() {
  return (
    <section className="mx-auto max-w-6xl px-6 py-16">
      <h2 className="text-center text-3xl font-bold">Everything you need to connect</h2>
      <div className="mt-10 grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
        {features.map((f) => (
          <div key={f.title} className="rounded-2xl border border-neutral-800 bg-neutral-900 p-6">
            <h3 className="text-lg font-semibold">{f.title}</h3>
            <p className="mt-2 text-neutral-400">{f.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
