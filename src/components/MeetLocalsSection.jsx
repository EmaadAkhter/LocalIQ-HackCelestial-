import { useMemo, useState } from 'react';
import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const meetupProfiles = [
  {
    id: 'p1',
    name: 'A',
    age: 28,
    gender: 'F',
    role: 'Local Guide · Fort & Colaba',
    avatar: 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=300&q=80',
    tags: ['Heritage walks', 'Filter chai spots', 'Art galleries'],
    match: '94%',
    matchBg: 'bg-tertiary text-on-tertiary',
    status: 'Available this week',
    statusDot: 'bg-tertiary',
    vibe: 'Culture',
    neighborhood: 'Fort',
  },
  {
    id: 'p2',
    name: 'B',
    age: 31,
    gender: 'M',
    role: 'Street Food Expert · Bandra',
    avatar: 'https://images.unsplash.com/photo-1472099645785-5658abf4ff4e?auto=format&fit=crop&w=300&q=80',
    tags: ['Night food trails', 'Khau galli', 'Vada pav culture'],
    match: '91%',
    matchBg: 'bg-primary text-on-primary',
    status: 'Available evenings',
    statusDot: 'bg-tertiary',
    vibe: 'Foodie',
    neighborhood: 'Bandra',
  },
  {
    id: 'p3',
    name: 'C',
    age: 26,
    gender: 'F',
    role: 'Craft Documenter · Dharavi',
    avatar: 'https://images.unsplash.com/photo-1488426862026-3ee34a7d66df?auto=format&fit=crop&w=300&q=80',
    tags: ['Pottery', 'Textile art', 'Community spaces'],
    match: '87%',
    matchBg: 'bg-primary-fixed text-on-primary-fixed',
    status: 'Weekends only',
    statusDot: 'bg-secondary',
    vibe: 'Chill',
    neighborhood: 'Dharavi',
  },
];

const vibeFilters = ['All', 'Foodie', 'Culture', 'Chill'];

export default function MeetLocalsSection({ id = 'meet-locals' }) {
  const [activeFilter, setActiveFilter] = useState('All');
  const [rsvps, setRsvps] = useState(['p1']);

  const filteredProfiles = useMemo(() => {
    if (activeFilter === 'All') return meetupProfiles;
    return meetupProfiles.filter((profile) => profile.vibe === activeFilter);
  }, [activeFilter]);

  const toggleRsvp = (profileId) => {
    setRsvps((current) =>
      current.includes(profileId)
        ? current.filter((id) => id !== profileId)
        : [...current, profileId]
    );
  };

  return (
    <section id={id} className="w-full px-5 py-space-xl bg-[#f2e6df]">
      <div className="max-w-7xl mx-auto flex flex-col gap-8">
        <motion.div
          className="flex flex-col md:flex-row md:items-end justify-between gap-4"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-col gap-2">
            <span className="font-label-sm text-label-sm tracking-[0.12em] uppercase text-primary font-bold">
              Meet Locals
            </span>
            <h2 className="font-[Manrope] text-[30px] md:text-[52px] leading-[0.95] tracking-[-0.04em] font-bold text-on-surface">
              RANDOM MEETUP.
              <br />
              <span className="font-[Newsreader] italic font-normal text-on-surface-variant">
                curated by affinity.
              </span>
            </h2>
          </div>
          <p className="font-body-md text-body-md text-on-surface-variant max-w-md leading-relaxed">
            Not chance. Not forced. Matched based on what you love about Mumbai, and connected
            through a shared moment in the city.
          </p>
        </motion.div>

        <motion.div
          className="rounded-2xl bg-[#f4ece7] p-4 shadow-sm border border-[#e4d6ce]"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-wrap gap-2">
            {vibeFilters.map((filter) => (
              <button
                key={filter}
                type="button"
                onClick={() => setActiveFilter(filter)}
                className={`rounded-full px-4 py-2 font-label-md text-label-md transition-colors ${
                  activeFilter === filter
                    ? 'bg-[#e86d46] text-on-primary shadow-sm'
                    : 'bg-[#f7f2ee] text-on-surface-variant hover:bg-[#efe5df]'
                }`}
              >
                {filter}
              </button>
            ))}
          </div>
        </motion.div>

        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-5"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {filteredProfiles.map((profile) => {
            const isRsvped = rsvps.includes(profile.id);

            return (
              <motion.div
                key={profile.id}
                className="rounded-[22px] bg-[#f7f3ee] overflow-hidden shadow-sm px-4 pt-4 pb-3 flex flex-col gap-4 border border-[#e7d8cf]"
                variants={scaleIn}
                whileHover={{
                  y: -6,
                  boxShadow: '0 16px 32px -6px rgba(46,39,36,0.14)',
                  transition: { duration: 0.28, ease: [0.22, 1, 0.36, 1] },
                }}
              >
                <div className="flex items-center gap-3">
                  <div className="relative shrink-0">
                    <img
                      src={profile.avatar}
                      alt={profile.name}
                      className="w-14 h-14 rounded-full object-cover ring-2 ring-[#f0e8e2]"
                    />
                    <motion.div
                      className={`absolute bottom-0 right-0 w-3.5 h-3.5 rounded-full ${profile.statusDot} ring-2 ring-[#f7f3ee]`}
                      animate={{ scale: [1, 1.3, 1] }}
                      transition={{ repeat: Infinity, duration: 2, ease: 'easeInOut' }}
                    />
                  </div>

                  <div className="flex items-center justify-between w-full min-w-0 gap-2">
                    <div className="flex flex-col min-w-0">
                      <span className="font-headline-sm text-headline-sm text-on-surface leading-none">{profile.name}</span>
                      <span className="font-label-md text-label-md text-on-surface-variant mt-1">{profile.age}, {profile.gender}</span>
                    </div>

                    <div className={`px-2.5 py-1 rounded-full font-label-sm text-label-sm font-bold ${profile.matchBg}`}>
                      {profile.match}
                    </div>
                  </div>
                </div>

                <div className="flex flex-wrap gap-2">
                  {profile.tags.map((tag) => (
                    <span
                      key={tag}
                      className="px-2.5 py-1 rounded-full bg-[#efe6e1] text-on-surface-variant font-label-sm text-label-sm"
                    >
                      {tag}
                    </span>
                  ))}
                </div>

                <div className="flex items-center justify-between gap-2 text-xs">
                  <div className="flex items-center gap-1.5">
                    <div className={`w-2 h-2 rounded-full ${profile.statusDot}`} />
                    <span className="font-label-md text-label-md text-on-surface-variant">{profile.status}</span>
                  </div>
                  <span className="font-label-sm text-label-sm text-on-surface-variant">{profile.neighborhood}</span>
                </div>

                <motion.button
                  type="button"
                  onClick={() => toggleRsvp(profile.id)}
                  className={`w-full py-3 rounded-xl font-label-md text-label-md flex items-center justify-center gap-1.5 transition-colors cursor-pointer ${
                    isRsvped
                      ? 'bg-[#df6b48] text-white hover:bg-[#d35e3f]'
                      : 'bg-[#e86d46] text-white hover:bg-[#d95d37]'
                  }`}
                  whileHover={{ scale: 1.02 }}
                  whileTap={{ scale: 0.97 }}
                  transition={{ duration: 0.18 }}
                >
                  <span className="material-symbols-outlined text-[18px]">{isRsvped ? 'check' : 'people'}</span>
                  {isRsvped ? 'RSVP confirmed' : 'Request meetup'}
                </motion.button>
              </motion.div>
            );
          })}
        </motion.div>
      </div>
    </section>
  );
}
