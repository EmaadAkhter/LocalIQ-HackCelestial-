import { Link } from 'react-router-dom';
import { useMemo, useState } from 'react';
import { guides } from '../data/mock';

export default function GuidesPage() {
  const [specialty, setSpecialty] = useState('All');
  const [language, setLanguage] = useState('All');
  const list = useMemo(
    () =>
      guides.filter((guide) => {
        if (specialty !== 'All' && !guide.specialties.includes(specialty)) return false;
        if (language !== 'All' && !guide.languages.includes(language)) return false;
        return true;
      }),
    [specialty, language],
  );

  return (
    <div className="max-w-6xl mx-auto px-5 py-8">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-4">
        <div>
          <p className="font-label-sm uppercase tracking-widest text-primary">Guide marketplace</p>
          <h1 className="font-[Manrope] text-[40px] font-bold tracking-[-0.04em]">Verified local guides</h1>
        </div>
        <Link to="/guide-studio" className="rounded-full bg-inverse-surface text-inverse-on-surface px-5 py-3 font-label-md">
          Open guide studio
        </Link>
      </div>

      <div className="flex flex-wrap gap-2 mt-6">
        {['All', 'Food', 'Heritage', 'Photography', 'Art', 'Nightlife'].map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setSpecialty(item)}
            className={`rounded-full px-3 py-1.5 font-label-md ${specialty === item ? 'bg-primary text-on-primary' : 'bg-surface-container'}`}
          >
            {item}
          </button>
        ))}
        {['All', 'English', 'Hindi', 'Marathi'].map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setLanguage(item)}
            className={`rounded-full px-3 py-1.5 font-label-md ${language === item ? 'bg-secondary-container' : 'bg-surface-container'}`}
          >
            {item}
          </button>
        ))}
      </div>

      <div className="grid md:grid-cols-2 gap-5 mt-8">
        {list.map((guide) => (
          <Link key={guide.id} to={`/guides/${guide.id}`} className="rounded-3xl bg-surface-container-lowest p-5 flex gap-4 shadow-sm">
            <img src={guide.photo} alt="" className="w-20 h-20 rounded-2xl object-cover" />
            <div className="flex-1">
              <div className="flex items-center gap-2">
                <h2 className="font-headline-md">{guide.name}</h2>
                {!guide.available && <span className="font-label-sm text-error">Unavailable</span>}
              </div>
              <p className="font-body-md text-on-surface-variant line-clamp-2">{guide.bio}</p>
              <p className="font-label-sm mt-2">
                ₹{guide.rate}/hr · {guide.rating}★ · {guide.tours} tours · {guide.personality}
              </p>
              <div className="flex flex-wrap gap-1 mt-2">
                {guide.verification.map((badge) => (
                  <span key={badge} className="rounded-full bg-tertiary-fixed text-on-tertiary-fixed px-2 py-0.5 font-label-sm">
                    {badge}
                  </span>
                ))}
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
