import { Link } from 'react-router-dom';
import { useLocalIQ } from '../context/LocalIQContext';
import { experiences } from '../data/mock';

export default function ProfilePage() {
  const {
    user,
    requireUser,
    taste,
    setTaste,
    personalization,
    setPersonalization,
    savedIds,
    bookings,
    setUser,
  } = useLocalIQ();

  const saved = experiences.filter((item) => savedIds.includes(item.id));

  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-5 py-20 text-center">
        <h1 className="font-[Manrope] text-[34px] font-bold">Your profile</h1>
        <p className="mt-3 text-on-surface-variant">
          Sign in to hold taste DNA, trust tier, and saved plans. Verification images never live in this database mock.
        </p>
        <button type="button" onClick={() => requireUser()} className="mt-5 rounded-full bg-primary-container text-on-primary px-5 py-3">
          Sign in
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-6xl mx-auto px-5 py-10">
      <div className="rounded-3xl bg-surface-container-lowest p-6 shadow-sm border border-outline-variant/60">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-5">
          <div className="flex items-center gap-4">
            <img src={user.photo} alt={user.name} className="h-16 w-16 rounded-full object-cover ring-2 ring-primary-container" />
            <div>
              <p className="font-label-sm uppercase tracking-[0.08em] text-primary">Trust tier {user.trustTier}</p>
              <h1 className="font-[Manrope] text-[28px] font-bold">{user.name}</h1>
              <p className="text-on-surface-variant">{user.email}</p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link to="/passport" className="rounded-full bg-primary-container text-on-primary px-5 py-3 font-label-md">
              Open passport
            </Link>
            <Link to="/guide-studio" className="rounded-full bg-surface-container px-5 py-3 font-label-md">
              Guide studio
            </Link>
          </div>
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-5 mt-8">
        <section className="rounded-3xl bg-surface-container-low p-5">
          <div className="flex items-center justify-between gap-3">
            <h2 className="font-headline-md">Taste profile</h2>
            <button type="button" onClick={() => setPersonalization((v) => !v)} className="font-label-md text-primary">
              {personalization ? 'Pause personalization' : 'Resume personalization'}
            </button>
          </div>
          <textarea
            value={taste.text}
            onChange={(e) => setTaste((current) => ({ ...current, text: e.target.value }))}
            className="mt-3 w-full min-h-[140px] rounded-2xl bg-surface-container-lowest p-3 font-body-md"
          />
          <p className="font-body-sm text-on-surface-variant mt-2">
            Edit the natural-language summary. Implicit signals still boost hidden gems and morning walks unless you pause.
          </p>
        </section>

        <section className="rounded-3xl bg-surface-container-lowest p-5">
          <h2 className="font-headline-md">Verification</h2>
          <p className="font-body-md text-on-surface-variant mt-2">
            Tier 1 is live. Raise the tier only for stranger-facing features.
          </p>
          <div className="flex flex-wrap gap-2 mt-4">
            <button type="button" onClick={() => setUser((c) => ({ ...c, trustTier: 1 }))} className="rounded-full bg-surface-container px-4 py-2">
              Tier 1
            </button>
            <button type="button" onClick={() => setUser((c) => ({ ...c, trustTier: 2 }))} className="rounded-full bg-surface-container px-4 py-2">
              ID verified
            </button>
            <button type="button" onClick={() => setUser((c) => ({ ...c, trustTier: 3 }))} className="rounded-full bg-surface-container px-4 py-2">
              Enhanced
            </button>
          </div>

          <div className="mt-6 space-y-4">
            <div>
              <h3 className="font-headline-sm">Saved</h3>
              <ul className="mt-2 space-y-2">
                {saved.length ? (
                  saved.map((item) => (
                    <li key={item.id}>
                      <Link to={`/experience/${item.id}`} className="font-label-md text-primary">{item.title}</Link>
                    </li>
                  ))
                ) : (
                  <li className="font-body-md text-on-surface-variant">No saved experiences yet.</li>
                )}
              </ul>
            </div>

            <div>
              <h3 className="font-headline-sm">Guide bookings</h3>
              <p className="font-body-md text-on-surface-variant">{bookings.length} requests</p>
            </div>
          </div>
        </section>
      </div>
    </div>
  );
}
