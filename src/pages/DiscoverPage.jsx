import { useMemo, useState } from 'react';
import { useLocation, useSearchParams } from 'react-router-dom';
import { motion } from 'motion/react';
import { staggerContainer, fadeUp } from '../lib/animations';
import ExperienceCard from '../components/ExperienceCard';
import { useLocalIQ } from '../context/LocalIQContext';

const categories = ['All', 'Food', 'Heritage', 'Art', 'Nature', 'Nightlife'];

export default function DiscoverPage() {
  const { rankedExperiences, raining, setRaining, hour, setHour, ignoreTaste, setIgnoreTaste } = useLocalIQ();
  const [params, setParams] = useSearchParams();
  const location = useLocation();
  const [category, setCategory] = useState('All');
  const [accessible, setAccessible] = useState(false);
  const [hiddenOnly, setHiddenOnly] = useState(
    params.get('filter') === 'hidden' || location.pathname === '/hidden-gems'
  );
  const [query, setQuery] = useState(params.get('q') || '');

  const feed = useMemo(() => {
    return rankedExperiences.filter((item) => {
      if (category !== 'All' && item.category !== category) return false;
      if (hiddenOnly && !item.hiddenGem) return false;
      if (accessible && !item.wheelchair) return false;
      if (query && !`${item.title} ${item.neighborhood} ${item.description}`.toLowerCase().includes(query.toLowerCase())) {
        return false;
      }
      return true;
    });
  }, [rankedExperiences, category, hiddenOnly, accessible, query]);

  const indoorShare = feed.slice(0, 5).filter((item) => item.rainSafe).length;

  return (
    <div className="max-w-[1600px] mx-auto px-5 py-8">
      <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-4 mb-8">
        <div>
          <p className="font-label-sm text-label-sm uppercase tracking-[0.12em] text-primary">Location → person</p>
          <h1 className="font-[Manrope] text-[36px] md:text-[48px] font-bold tracking-[-0.04em] leading-none">
            Right Now in Mumbai
          </h1>
          <p className="font-[Newsreader] italic text-[18px] text-on-surface-variant mt-2">
            Feasible for you, at this hour — not just highly rated.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setRaining((v) => !v)}
            className={`rounded-full px-4 py-2 font-label-md ${raining ? 'bg-primary text-on-primary' : 'bg-surface-container'}`}
          >
            {raining ? 'Rain in 20 min' : 'Simulate rain'}
          </button>
          <label className="rounded-full bg-surface-container px-4 py-2 font-label-md flex items-center gap-2">
            Hour
            <input
              type="range"
              min="6"
              max="23"
              value={hour}
              onChange={(e) => setHour(Number(e.target.value))}
            />
            <span className="font-mono text-sm">{hour}:00</span>
          </label>
          <button
            type="button"
            onClick={() => setIgnoreTaste((v) => !v)}
            className="rounded-full bg-surface-container px-4 py-2 font-label-md"
          >
            {ignoreTaste ? 'Using taste profile' : 'Surprise me'}
          </button>
        </div>
      </div>

      {raining && (
        <div className="mb-6 rounded-2xl bg-surface-container p-4 font-body-md text-on-surface">
          Rain expected — indoor options now prioritized. {indoorShare} of the top 5 currently showing are rain-safe.
        </div>
      )}

      <div className="flex flex-wrap gap-2 mb-6">
        {categories.map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setCategory(item)}
            className={`px-3.5 py-1.5 rounded-full font-label-md ${
              category === item ? 'bg-primary text-on-primary' : 'bg-surface-container'
            }`}
          >
            {item}
          </button>
        ))}
        <button
          type="button"
          onClick={() => {
            setHiddenOnly((v) => !v);
            setParams(hiddenOnly ? {} : { filter: 'hidden' });
          }}
          className={`px-3.5 py-1.5 rounded-full font-label-md ${hiddenOnly ? 'bg-tertiary text-on-tertiary' : 'bg-surface-container'}`}
        >
          Hidden gems
        </button>
        <button
          type="button"
          onClick={() => setAccessible((v) => !v)}
          className={`px-3.5 py-1.5 rounded-full font-label-md ${accessible ? 'bg-tertiary text-on-tertiary' : 'bg-surface-container'}`}
        >
          Wheelchair accessible
        </button>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Neighborhood, food, craft…"
          className="ml-auto rounded-full bg-surface-container px-4 py-2 min-w-[220px] font-body-md"
        />
      </div>

      <motion.div
        className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-5"
        variants={staggerContainer}
        initial="hidden"
        animate="visible"
      >
        {feed.map((experience) => (
          <ExperienceCard key={experience.id} experience={experience} />
        ))}
      </motion.div>

      <motion.section className="mt-12 rounded-3xl bg-surface-container-low p-6" variants={fadeUp} initial="hidden" animate="visible">
        <p className="font-label-sm text-label-sm uppercase tracking-widest text-primary">Location → location</p>
        <h2 className="font-headline-lg text-headline-lg mt-1">Natural clusters</h2>
        <div className="mt-4 grid md:grid-cols-3 gap-4">
          {[
            { title: 'Kala Ghoda art cluster', copy: 'Galleries, covered arcades, monsoon-proof cafés.' },
            { title: 'Best 3-stop food walk in 2 hours', copy: 'Bohri Mohalla → Taj Ice Cream → Minara stretch.' },
            { title: 'Hidden corridor', copy: 'Most tourists miss the Worli Koliwada lane between the sea wall and fort.' },
          ].map((cluster) => (
            <div key={cluster.title} className="rounded-2xl bg-surface-container-lowest p-4">
              <h3 className="font-headline-sm text-headline-sm">{cluster.title}</h3>
              <p className="font-body-md text-on-surface-variant mt-1">{cluster.copy}</p>
            </div>
          ))}
        </div>
      </motion.section>
    </div>
  );
}
