import { Link } from 'react-router-dom';
import { experiences } from '../data/mock';
import { useLocalIQ } from '../context/LocalIQContext';

export default function PassportPage() {
  const { user, logs, badges, badgeCatalog, requireUser } = useLocalIQ();

  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-5 py-20 text-center">
        <h1 className="font-headline-lg">Experience passport</h1>
        <p className="text-on-surface-variant mt-2">Sign in to keep a living record of outings, badges, and share cards.</p>
        <button type="button" onClick={() => requireUser()} className="mt-4 rounded-full bg-primary-container text-on-primary px-5 py-3">
          Sign in
        </button>
      </div>
    );
  }

  const hidden = logs.filter((log) => experiences.find((item) => item.id === log.experienceId)?.hiddenGem).length;
  const neighborhoods = [...new Set(logs.map((log) => experiences.find((item) => item.id === log.experienceId)?.neighborhood).filter(Boolean))];

  return (
    <div className="max-w-6xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">Experience wallet</p>
      <h1 className="font-[Manrope] text-[40px] font-bold">Your Mumbai passport</h1>

      <div className="grid md:grid-cols-4 gap-4 mt-6">
        {[
          [logs.length, 'Experiences'],
          [hidden, 'Hidden gems'],
          [neighborhoods.length, 'Neighborhoods'],
          [badges.length, 'Badges'],
        ].map(([value, label]) => (
          <div key={label} className="rounded-2xl bg-surface-container p-4">
            <p className="font-[Manrope] text-[28px] font-bold">{value}</p>
            <p className="font-label-md text-on-surface-variant">{label}</p>
          </div>
        ))}
      </div>

      <div className="mt-8 rounded-3xl bg-surface-container-low p-6">
        <p className="font-headline-sm">Map of places visited</p>
        <div className="mt-4 grid grid-cols-2 md:grid-cols-4 gap-3">
          {logs.map((log) => {
            const exp = experiences.find((item) => item.id === log.experienceId);
            if (!exp) return null;
            return (
              <Link key={log.id} to={`/experience/${exp.id}`} className="rounded-2xl overflow-hidden bg-surface-container-lowest">
                <img src={exp.img} alt="" className="h-24 w-full object-cover" />
                <p className="p-2 font-label-md">{exp.neighborhood}</p>
              </Link>
            );
          })}
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-6 mt-8">
        <div>
          <h2 className="font-headline-md mb-3">Timeline</h2>
          <ul className="space-y-3">
            {logs.map((log) => {
              const exp = experiences.find((item) => item.id === log.experienceId);
              return (
                <li key={log.id} className="rounded-2xl bg-surface-container-lowest p-4">
                  <p className="font-headline-sm">{exp?.title}</p>
                  <p className="font-body-sm text-on-surface-variant">{new Date(log.completedAt).toLocaleString()} · {log.summary}</p>
                </li>
              );
            })}
          </ul>
        </div>
        <div>
          <h2 className="font-headline-md mb-3">Badges</h2>
          <div className="space-y-3">
            {badgeCatalog.map((badge) => {
              const earned = badges.includes(badge.id);
              return (
                <div key={badge.id} className={`rounded-2xl p-4 flex gap-3 ${earned ? 'bg-tertiary-fixed' : 'bg-surface-container'}`}>
                  <span className="material-symbols-outlined">{badge.icon}</span>
                  <div>
                    <p className="font-headline-sm">{badge.name}</p>
                    <p className="font-body-sm">{badge.rule} {earned ? '· earned' : ''}</p>
                  </div>
                </div>
              );
            })}
          </div>
          <div className="mt-6 rounded-3xl bg-inverse-surface text-inverse-on-surface p-5">
            <p className="font-label-sm uppercase text-primary-fixed">My Mumbai Month</p>
            <p className="font-headline-md mt-2">{logs.length} outings · {hidden} hidden gems · {badges.length} badges</p>
            <button type="button" className="mt-4 rounded-full bg-primary-container text-on-primary px-4 py-2 font-label-md">
              Share card (demo)
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
