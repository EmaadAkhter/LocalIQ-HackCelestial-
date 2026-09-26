const HIGHLIGHTS = [
  {
    title: "Feasibility-first",
    body: "Every result already fits your time, budget, opening hours, and travel distance — before ranking even begins.",
  },
  {
    title: "Explainable picks",
    body: "Each recommendation says why it fits, in plain language. No black box.",
  },
  {
    title: "Live re-ranking",
    body: "Change your budget or available time and watch the shortlist reshuffle instantly.",
  },
];

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-5xl flex-1 flex-col gap-16 px-6 py-20">
      <header className="flex flex-col gap-6">
        <span className="w-fit rounded-full border border-border bg-card px-3 py-1 text-xs font-medium uppercase tracking-wide text-muted">
          HackCelestial 3.0 · Team Nexify
        </span>
        <h1 className="max-w-2xl text-4xl font-semibold leading-tight tracking-tight sm:text-5xl">
          LocalIQ
        </h1>
        <p className="max-w-2xl text-lg text-muted">
          Not &ldquo;what&rsquo;s nearby&rdquo; — what you can actually experience right now.
          LocalIQ turns your real constraints into a ranked, explainable shortlist of doable
          local experiences.
        </p>
      </header>

      <section className="grid gap-6 sm:grid-cols-3">
        {HIGHLIGHTS.map((item) => (
          <div
            key={item.title}
            className="rounded-2xl border border-border bg-card p-6"
          >
            <h2 className="text-base font-semibold">{item.title}</h2>
            <p className="mt-2 text-sm text-muted">{item.body}</p>
          </div>
        ))}
      </section>

      <footer className="text-sm text-muted">
        Build in progress. See{" "}
        <code className="rounded bg-card px-1.5 py-0.5">PLAN.md</code> for the full roadmap.
      </footer>
    </main>
  );
}
