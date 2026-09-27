import { useMemo, useState } from 'react';
import { motion } from 'motion/react';
import { fadeUp, revealUp, spring, staggerContainer, viewportOnce } from '../lib/animations';
import { usePointerTilt } from '../lib/motionHooks';

const cards = [
  {
    id: 'food-after-dark',
    category: 'Food',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCz20I1rra3ZkCqOKxlpIfGlhpQjxVsPmo7E5ygxUCPr_ZS6DZgtvoiTiFsqAq0LRhyfYeocNJFacAR6YTjEkT-XQ_XUZgeTQ9M5EymdDFv3Yht7Ad5iV05W_kmedsG4fDbIniQ1HxnsGKN2ef-fZ3Ine7DPMxTtDg7OaDfR3hGy9_QSeMNqzHFu8WPOHx8y58i1c_YZj8RPKDtni9hIrIh3HjIRIrha_TlBa7Dio8-piSWt9IFVrVzNQ',
    imgAlt: 'Night street food in Bohri Mohalla Mumbai',
    neighborhood: 'Bohri Mohalla • Khau Galli',
    match: '96% match',
    matchColor: 'bg-tertiary text-on-tertiary',
    time: 'Evening • 8:30 PM – Late',
    cost: '≈ ₹400 for two',
    title: 'Street food after dark',
    description: 'Crisp baida roti, hand-churned sancha ice cream at Taj Ice Cream, and the aromatic warmth of 130-year-old culinary traditions.',
  },
  {
    id: 'dock-art',
    category: 'Art',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDolZZnCfsE9AaK-o3WgIomzGixbZ2iADivujy9YtsTXDD8vBpjkUJZuugSjvnusEFn-qGL0gfztBliib7v1m8b788EQKp95iWPhDyqXXvAtQiVuA7W6NnjQefq8FoyFrYqnedwNpaDL0_fl3MfHbwnz2psISlEIgliY95-UjCwlZkSFbyF5xGHOUGeAGcQPbKlVoBnKsWAOnxUspX66WFibg1pq8hm6YknNMsyX3p-5CEPpEjEwCREjA',
    imgAlt: 'Sassoon Docks art project Colaba Mumbai',
    neighborhood: 'Sassoon Docks • Colaba',
    match: '92% match',
    matchColor: 'bg-primary-container text-on-primary',
    time: 'Afternoon • 3:00 PM – Sunset',
    cost: 'Free',
    title: 'Sassoon Docks Art Project',
    description: 'Stroll through historic dock warehouses reimagined by contemporary muralists, with open sea breeze and tactile textures.',
  },
  {
    id: 'horniman-circle',
    category: 'Heritage',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCiasWkb3umfWgDxgA-rJ6t-xb5bmfBMWyfeEb1j-F4cfbYKYrWjArGOzN7t7QVEOnqrxQFOI1ZhpQq3jF9NeD5ZfdCKZLi3TR30SgEscSpOdR2Cq08ph3dNR-DBFFxbXvGkrv-4x1qi5rnw-Q5L9MUTaYCEkM1eABA6MYd9jZ1E3WMuBOizUXxd5wyTC0kzFVhh4LfHtAw5vu5_vwNid3cGeZlEHxNc2Xyu2cPkyDg7qBaI3s5JT6V-w',
    imgAlt: 'Horniman Circle Gardens heritage walk',
    neighborhood: 'Horniman Circle • Fort',
    match: '88% match',
    matchColor: 'bg-secondary-container text-on-secondary-container',
    time: 'Morning • 7:00 – 10:00 AM',
    cost: '≈ ₹80 for chai',
    title: 'Heritage walk & filter chai',
    description: `Colonial stone arcades, banyan-lined garden walks, and the quiet ritual of morning filter coffee in Mumbai's banking district.`,
  },
];

const filters = ['All', 'Food', 'Heritage', 'Art', 'Nightlife', 'Nature'];

function ExperienceCard({ card, saved, onToggleSave }) {
  const tilt = usePointerTilt({ max: 6 });
  return (
    <motion.div
      variants={revealUp}
      className="h-full"
      style={{ perspective: 900 }}
    >
      <motion.div
        {...tilt.bind}
        className="relative flex flex-col h-full rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm group"
        style={{ rotateX: tilt.rotateX, rotateY: tilt.rotateY, transformStyle: 'preserve-3d' }}
        whileHover={{ boxShadow: '0 20px 40px -8px rgba(46,39,36,0.15)' }}
        transition={spring}
      >
        <div className="relative h-64 overflow-hidden">
          <motion.img
            className="w-full h-full object-cover"
            src={card.imgSrc}
            alt={card.imgAlt}
            whileHover={{ scale: 1.06 }}
            transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
          />
          {!tilt.reduce && (
            <motion.div
              className="absolute inset-0 pointer-events-none mix-blend-soft-light opacity-0 group-hover:opacity-100 transition-opacity"
              style={{ background: tilt.spotlight }}
            />
          )}
          <div className="absolute top-3 left-3 bg-surface-container-lowest/90 backdrop-blur-sm px-3 py-1 rounded-full font-label-sm text-label-sm text-on-surface">
            {card.neighborhood}
          </div>
          <div className={`absolute bottom-3 right-3 px-3 py-0.5 rounded-full font-label-sm text-label-sm font-bold ${card.matchColor}`}>
            {card.match}
          </div>
        </div>
        <div className="p-4 flex flex-col flex-1 justify-between gap-3">
          <div className="flex flex-col gap-1">
            <div className="flex items-center justify-between text-on-surface-variant font-label-sm text-label-sm">
              <span>{card.time}</span>
              <span className="font-bold text-on-surface">{card.cost}</span>
            </div>
            <h3 className="font-headline-md text-headline-md text-on-surface group-hover:text-primary transition-colors duration-200">
              {card.title}
            </h3>
            <p className="font-[Newsreader] text-[14px] leading-[20px] text-on-surface-variant">
              {card.description}
            </p>
          </div>
          <div className="pt-1 flex items-center justify-between">
            <motion.button
              type="button"
              className="font-label-md text-label-md text-primary font-semibold flex items-center gap-1 cursor-pointer"
              whileHover={{ x: 3 }}
              transition={{ duration: 0.18 }}
            >
              Explore Route{' '}
              <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
            </motion.button>
            <motion.button
              type="button"
              onClick={() => onToggleSave(card.id)}
              className="material-symbols-outlined text-[20px] transition-colors cursor-pointer"
              whileHover={{ scale: 1.2 }}
              whileTap={{ scale: 0.88 }}
              animate={saved ? { scale: [1, 1.35, 1] } : { scale: 1 }}
              transition={spring}
              aria-label={saved ? 'Remove bookmark' : 'Save to bookmarks'}
              style={{ color: saved ? '#B52603' : 'rgba(91,64,58,0.45)' }}
            >
              {saved ? 'bookmark_added' : 'bookmark'}
            </motion.button>
          </div>
        </div>
      </motion.div>
    </motion.div>
  );
}

export default function DiscoverySection({ id = 'explore' }) {
  const [activeFilter, setActiveFilter] = useState('All');
  const [query, setQuery] = useState('');
  const [saved, setSaved] = useState(['food-after-dark']);

  const filteredCards = useMemo(() => {
    const search = query.trim().toLowerCase();

    return cards.filter((card) => {
      const matchesFilter = activeFilter === 'All' || card.category === activeFilter;
      const searchableText = [
        card.title,
        card.description,
        card.neighborhood,
        card.category,
      ].join(' ').toLowerCase();

      const matchesSearch = !search || searchableText.includes(search);
      return matchesFilter && matchesSearch;
    });
  }, [activeFilter, query]);

  const toggleSave = (cardId) => {
    setSaved((current) =>
      current.includes(cardId)
        ? current.filter((item) => item !== cardId)
        : [...current, cardId]
    );
  };

  return (
    <section id={id} className="w-full px-5 py-space-xl bg-surface-container-low">
      <div className="max-w-7xl mx-auto flex flex-col gap-6">
        <motion.div
          className="flex flex-col md:flex-row md:items-end justify-between gap-3"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div>
            <span className="font-label-sm text-label-sm tracking-widest uppercase text-primary font-bold">
              Starting Points
            </span>
            <h2 className="font-[Manrope] text-[32px] md:text-[36px] leading-[1.1] tracking-[-0.03em] font-bold text-on-surface mt-2">
              YOU DON'T NEED A PLAN.
              <br />
              <span className="font-[Newsreader] italic font-normal text-on-surface-variant">
                You just need a starting point.
              </span>
            </h2>
          </div>
          <p className="font-body-md text-body-md text-on-surface-variant max-w-sm">
            No algorithmic noise or tourist traps. Curated neighborhood chapters built around
            moments, not itineraries.
          </p>
        </motion.div>

        <motion.div
          className="rounded-2xl bg-surface-container-lowest p-4 shadow-sm border border-outline-variant/60"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div className="flex flex-1 items-center gap-2 rounded-full bg-surface-container px-3 py-2.5">
              <span className="material-symbols-outlined text-[18px] text-primary">search</span>
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search food, art, heritage, or neighborhood..."
                className="w-full bg-transparent text-body-md text-on-surface placeholder:text-on-surface-variant/70 focus:outline-none"
                aria-label="Search experiences"
              />
            </div>

            <div className="flex items-center gap-2 text-label-md text-on-surface-variant">
              <span className="material-symbols-outlined text-[18px]">filter_alt</span>
              <span>{filteredCards.length} matches</span>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            {filters.map((filter) => {
              const active = activeFilter === filter;
              return (
                <motion.button
                  key={filter}
                  type="button"
                  onClick={() => setActiveFilter(filter)}
                  className={`relative rounded-full px-3 py-1.5 font-label-md text-label-md ${
                    active
                      ? 'text-on-primary'
                      : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high'
                  }`}
                  whileTap={{ scale: 0.94 }}
                  transition={spring}
                >
                  {active && (
                    <motion.span
                      layoutId="discovery-filter-pill"
                      className="absolute inset-0 rounded-full bg-primary-container"
                      transition={spring}
                    />
                  )}
                  <span className="relative z-10">{filter}</span>
                </motion.button>
              );
            })}
          </div>
        </motion.div>

        {filteredCards.length === 0 ? (
          <div className="rounded-2xl border border-dashed border-outline-variant bg-surface-container-lowest p-8 text-center">
            <p className="font-headline-sm text-headline-sm text-on-surface">No matches yet</p>
            <p className="mt-2 font-body-md text-body-md text-on-surface-variant">
              Try a different vibe or search term like “food”, “heritage”, or “Bandra”.
            </p>
          </div>
        ) : (
          <motion.div
            className="grid grid-cols-1 md:grid-cols-3 gap-4 items-stretch"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={viewportOnce}
          >
            {filteredCards.map((card) => (
              <ExperienceCard
                key={card.id}
                card={card}
                saved={saved.includes(card.id)}
                onToggleSave={toggleSave}
              />
            ))}
          </motion.div>
        )}
      </div>
    </section>
  );
}
