import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { motion, useTransform } from 'motion/react';
import { lineRise, revealUp, spring, springSnappy } from '../lib/animations';
import { usePointerParallax, usePointerTilt } from '../lib/motionHooks';

const vibePills = [
  'Food & Chai',
  'Culture & Heritage',
  'Hidden Gems',
  'Quiet Nightlife',
  'Alley Walks',
  'Something Different',
];

// Orchestrated page-load sequence: overline → headline lines → subhead → search.
const heroStage = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.09, delayChildren: 0.05 } },
};

const headlineStage = {
  hidden: {},
  visible: { transition: { staggerChildren: 0.12 } },
};

export default function HeroSection({ id = 'top', user }) {
  const greeting = user ? `Hi, ${user.name.split(' ')[0]}` : 'Discover Local. Smarter.';
  const [query, setQuery] = useState('something chill near Bandra tonight');
  const [activeVibe, setActiveVibe] = useState('Food & Chai');
  const navigate = useNavigate();

  const parallax = usePointerParallax();
  const orbAX = useTransform(parallax.x, [-1, 1], [26, -26]);
  const orbAY = useTransform(parallax.y, [-1, 1], [20, -20]);
  const orbBX = useTransform(parallax.x, [-1, 1], [-20, 20]);
  const orbBY = useTransform(parallax.y, [-1, 1], [-16, 16]);

  const tilt = usePointerTilt({ max: 9 });

  const goDiscover = (extra = {}) => {
    const params = new URLSearchParams();
    const q = (extra.query ?? query).trim();
    const vibe = extra.vibe ?? activeVibe;
    if (q) params.set('q', q);
    if (vibe) params.set('vibe', vibe);
    navigate(`/discover${params.toString() ? `?${params}` : ''}`);
  };

  return (
    <section id={id} className="relative w-full px-5 pt-space-xl pb-space-xl overflow-hidden">
      {/* Signature moment: a slow coral aurora drifts behind the type. Off under reduced-motion. */}
      {!parallax.reduce && (
        <motion.div
          aria-hidden
          className="absolute -inset-[30%] pointer-events-none opacity-[0.22] blur-[90px]"
          style={{
            background:
              'conic-gradient(from 120deg at 60% 40%, #FF5A36, #b52603, #fff8f6, #FF5A36)',
            x: orbAX,
            y: orbAY,
          }}
          animate={{ rotate: 360 }}
          transition={{ repeat: Infinity, duration: 40, ease: 'linear' }}
        />
      )}
      <motion.div
        className="absolute top-1/2 -left-20 w-80 h-80 rounded-full bg-surface-container-high/50 blur-2xl pointer-events-none"
        style={{ x: orbBX, y: orbBY }}
      />

      <motion.div
        className="relative max-w-7xl mx-auto flex flex-col gap-6"
        variants={heroStage}
        initial="hidden"
        animate="visible"
      >
        {/* Overline — plain sentence-case, one live cue, no magazine meta */}
        <motion.div
          className="flex items-center gap-2"
          variants={revealUp}
        >
          <motion.span
            className="w-2 h-2 rounded-full bg-primary-container"
            animate={{ scale: [1, 1.4, 1] }}
            transition={{ repeat: Infinity, duration: 2.4, ease: 'easeInOut' }}
          />
          <span className="font-body-md text-body-md text-on-surface-variant">
            Live across Mumbai, read by the people who live there
          </span>
        </motion.div>

        {/* Asymmetric hero grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-end">
          {/* Left: Editorial copy */}
          <div className="lg:col-span-8 flex flex-col gap-3">
            <motion.span
              className="font-headline-sm text-headline-sm text-primary uppercase tracking-tight"
              variants={revealUp}
            >
              {greeting}
            </motion.span>

            <motion.h1
              className="font-[Manrope] text-[44px] md:text-[64px] lg:text-[76px] leading-[0.97] tracking-[-0.04em] text-on-surface font-bold"
              variants={headlineStage}
            >
              <span className="block overflow-hidden pb-[0.08em]">
                <motion.span className="block" variants={lineRise}>
                  WHAT DO YOU
                </motion.span>
              </span>
              <span className="block overflow-hidden pb-[0.08em]">
                <motion.span className="block" variants={lineRise}>
                  <span className="font-[Newsreader] italic font-normal text-primary-container">
                    feel like
                  </span>{' '}
                  DOING?
                </motion.span>
              </span>
            </motion.h1>

            <motion.p
              className="font-[Newsreader] text-[20px] leading-[28px] text-on-surface-variant max-w-2xl mt-1"
              variants={revealUp}
            >
              Tell us what you're in the mood for. We'll unearth quiet corners, storied
              bakeries, and tucked-away courtyards that fit your tempo.
            </motion.p>
          </div>

          {/* Right: Floating hero card with cursor tilt */}
          <motion.div
            className="lg:col-span-4 flex flex-col gap-2"
            variants={revealUp}
            style={{ perspective: 900 }}
          >
            <motion.div
              {...tilt.bind}
              className="relative rounded-2xl overflow-hidden bg-surface-container shadow-md group"
              style={{ rotateX: tilt.rotateX, rotateY: tilt.rotateY, transformStyle: 'preserve-3d' }}
            >
              <img
                className="w-full h-64 object-cover"
                src="https://lh3.googleusercontent.com/aida-public/AB6AXuCiasWkb3umfWgDxgA-rJ6t-xb5bmfBMWyfeEb1j-F4cfbYKYrWjArGOzN7t7QVEOnqrxQFOI1ZhpQq3jF9NeD5ZfdCKZLi3TR30SgEscSpOdR2Cq08ph3dNR-DBFFxbXvGkrv-4x1qi5rnw-Q5L9MUTaYCEkM1eABA6MYd9jZ1E3WMuBOizUXxd5wyTC0kzFVhh4LfHtAw5vu5_vwNid3cGeZlEHxNc2Xyu2cPkyDg7qBaI3s5JT6V-w"
                alt="Golden hour over the Arabian Sea at Bandra Bandstand"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-on-surface/80 via-transparent to-transparent" />
              {!tilt.reduce && (
                <motion.div
                  className="absolute inset-0 pointer-events-none mix-blend-soft-light"
                  style={{ background: tilt.spotlight }}
                />
              )}
              <div className="absolute bottom-0 left-0 p-4 text-on-primary">
                <span className="font-label-sm text-label-sm uppercase tracking-wider text-primary-fixed">
                  Featured Horizon
                </span>
                <p className="font-headline-sm text-headline-sm leading-tight text-white">
                  Bandra Bandstand at 6:15 PM
                </p>
                <p className="font-body-editorial-italic text-body-editorial-italic text-outline-variant">
                  Salt air, vintage sea-facing bungalows, and slow filter coffee.
                </p>
              </div>
            </motion.div>
          </motion.div>
        </div>

        {/* Conversational Search Module */}
        <motion.div
          className="w-full bg-surface-container-lowest p-3 sm:p-4 rounded-2xl shadow-xl flex flex-col gap-3 mt-1"
          variants={revealUp}
        >
          <form
            className="flex flex-col md:flex-row items-stretch md:items-center gap-3"
            onSubmit={(e) => {
              e.preventDefault();
              goDiscover();
            }}
          >
            <div className="flex items-center gap-2 flex-1 px-3 py-2 bg-surface-container rounded-xl">
              <span className="material-symbols-outlined text-primary-container">explore</span>
              <input
                className="w-full bg-transparent font-body-lg text-body-lg text-on-surface placeholder:text-on-surface-variant/60 focus:outline-none py-1"
                placeholder="Try 'something chill near Bandra tonight' or 'quiet filter kaapi in Fort'..."
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                aria-label="Describe what you're in the mood for"
              />
            </div>
            <motion.button
              className="bg-primary-container text-on-primary font-label-lg text-label-lg px-6 py-3 rounded-xl shadow-md flex items-center justify-center gap-2 shrink-0 cursor-pointer"
              type="submit"
              whileHover={{ scale: 1.03, backgroundColor: '#b52603' }}
              whileTap={{ scale: 0.96 }}
              transition={springSnappy}
            >
              <span>{user ? 'Find my vibe' : 'Find something'}</span>
              <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
            </motion.button>
          </form>

          {/* Vibe pills */}
          <div className="flex items-center gap-2 flex-wrap pt-1">
            <span className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-wider mr-1">
              Vibe:
            </span>
            {vibePills.map((pill) => {
              const active = activeVibe === pill;
              return (
                <motion.button
                  key={pill}
                  className={`relative px-3 py-1 rounded-full font-label-md text-label-md ${
                    active ? 'text-on-primary' : 'bg-surface-container hover:bg-surface-container-high text-on-surface'
                  }`}
                  onClick={() => {
                    setActiveVibe(pill);
                    goDiscover({ vibe: pill });
                  }}
                  type="button"
                  whileHover={{ y: -1 }}
                  whileTap={{ scale: 0.95 }}
                  transition={spring}
                >
                  {active && (
                    <motion.span
                      layoutId="hero-vibe-pill"
                      className="absolute inset-0 rounded-full bg-primary shadow-sm"
                      transition={spring}
                    />
                  )}
                  <span className="relative z-10">{pill}</span>
                </motion.button>
              );
            })}
          </div>
        </motion.div>
      </motion.div>
    </section>
  );
}
