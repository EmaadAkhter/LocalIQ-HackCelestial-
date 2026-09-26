import { motion } from 'motion/react';
import {
  fadeUp,
  heroTitle,
  heroSubtitle,
  heroCTA,
  heroImage,
  staggerContainer,
  viewportOnce,
} from '../lib/animations';

const vibePills = [
  { label: 'Food & Chai', active: true },
  { label: 'Culture & Heritage', active: false },
  { label: 'Hidden Gems', active: false },
  { label: 'Quiet Nightlife', active: false },
  { label: 'Alley Walks', active: false },
  { label: 'Something Different', active: false },
];

export default function HeroSection() {
  return (
    <section className="relative w-full px-5 pt-space-xl pb-space-xl overflow-hidden">
      {/* Atmospheric gradient orbs */}
      <div className="absolute -top-24 -right-24 w-96 h-96 rounded-full bg-primary-container/10 blur-3xl pointer-events-none" />
      <div className="absolute top-1/2 -left-20 w-80 h-80 rounded-full bg-surface-container-high/60 blur-2xl pointer-events-none" />

      <div className="relative max-w-7xl mx-auto flex flex-col gap-6">
        {/* Magazine overline */}
        <motion.div
          className="flex flex-col sm:flex-row sm:items-baseline justify-between gap-2"
          variants={fadeUp}
          initial="hidden"
          animate="visible"
        >
          <div className="flex items-center gap-2">
            <motion.span
              className="w-2 h-2 rounded-full bg-primary-container"
              animate={{ scale: [1, 1.4, 1] }}
              transition={{ repeat: Infinity, duration: 2.4, ease: 'easeInOut' }}
            />
            <span className="font-label-md text-label-md tracking-widest uppercase text-on-surface-variant">
              Mumbai Neighborhood Intelligence • Issue No. 07
            </span>
          </div>
          <span className="font-body-editorial-italic text-body-editorial-italic text-on-surface-variant">
            South Bombay to Suburbs • Curated by 140+ Locals
          </span>
        </motion.div>

        {/* Asymmetric hero grid */}
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-end">
          {/* Left: Editorial copy */}
          <div className="lg:col-span-8 flex flex-col gap-3">
            <motion.span
              className="font-headline-sm text-headline-sm text-primary uppercase tracking-tight"
              variants={fadeUp}
              initial="hidden"
              animate="visible"
            >
              Discover Local. Smarter.
            </motion.span>

            <motion.h1
              className="font-[Manrope] text-[44px] md:text-[64px] lg:text-[76px] leading-[0.97] tracking-[-0.04em] text-on-surface font-bold"
              variants={heroTitle}
              initial="hidden"
              animate="visible"
            >
              WHAT DO YOU
              <br />
              <span className="font-[Newsreader] italic font-normal text-primary-container">
                feel like
              </span>{' '}
              DOING?
            </motion.h1>

            <motion.p
              className="font-[Newsreader] text-[20px] leading-[28px] text-on-surface-variant max-w-2xl mt-1"
              variants={heroSubtitle}
              initial="hidden"
              animate="visible"
            >
              Tell us what you're in the mood for. We'll unearth quiet corners, storied
              bakeries, and tucked-away courtyards that fit your tempo.
            </motion.p>
          </div>

          {/* Right: Floating hero card */}
          <motion.div
            className="lg:col-span-4 flex flex-col gap-2"
            variants={heroImage}
            initial="hidden"
            animate="visible"
          >
            <div className="relative rounded-2xl overflow-hidden bg-surface-container shadow-md group">
              <motion.img
                className="w-full h-64 object-cover"
                src="https://lh3.googleusercontent.com/aida-public/AB6AXuCiasWkb3umfWgDxgA-rJ6t-xb5bmfBMWyfeEb1j-F4cfbYKYrWjArGOzN7t7QVEOnqrxQFOI1ZhpQq3jF9NeD5ZfdCKZLi3TR30SgEscSpOdR2Cq08ph3dNR-DBFFxbXvGkrv-4x1qi5rnw-Q5L9MUTaYCEkM1eABA6MYd9jZ1E3WMuBOizUXxd5wyTC0kzFVhh4LfHtAw5vu5_vwNid3cGeZlEHxNc2Xyu2cPkyDg7qBaI3s5JT6V-w"
                alt="Golden hour over the Arabian Sea at Bandra Bandstand"
                whileHover={{ scale: 1.05 }}
                transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
              />
              <div className="absolute inset-0 bg-gradient-to-t from-on-surface/80 via-transparent to-transparent" />
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
            </div>
          </motion.div>
        </div>

        {/* Conversational Search Module */}
        <motion.div
          className="w-full bg-surface-container-lowest p-3 sm:p-4 rounded-2xl shadow-xl flex flex-col gap-3 mt-1"
          variants={heroCTA}
          initial="hidden"
          animate="visible"
        >
          <form
            className="flex flex-col md:flex-row items-stretch md:items-center gap-3"
            onSubmit={(e) => e.preventDefault()}
          >
            <div className="flex items-center gap-2 flex-1 px-3 py-2 bg-surface-container rounded-xl">
              <span className="material-symbols-outlined text-primary-container">explore</span>
              <input
                className="w-full bg-transparent font-body-lg text-body-lg text-on-surface placeholder:text-on-surface-variant/60 focus:outline-none py-1"
                placeholder="Try 'something chill near Bandra tonight' or 'quiet filter kaapi in Fort'..."
                type="text"
                defaultValue="something chill near Bandra tonight"
              />
            </div>
            <motion.button
              className="bg-primary-container hover:bg-primary text-on-primary font-label-lg text-label-lg px-6 py-3 rounded-xl transition-colors shadow-md flex items-center justify-center gap-2 shrink-0 cursor-pointer"
              type="submit"
              whileHover={{ scale: 1.03, y: -1 }}
              whileTap={{ scale: 0.96 }}
              transition={{ duration: 0.18 }}
            >
              <span>Find something</span>
              <span className="material-symbols-outlined text-[18px]">arrow_forward</span>
            </motion.button>
          </form>

          {/* Vibe pills */}
          <motion.div
            className="flex items-center gap-2 flex-wrap pt-1"
            variants={staggerContainer}
            initial="hidden"
            animate="visible"
          >
            <span className="font-label-sm text-label-sm text-on-surface-variant uppercase tracking-wider mr-1">
              Vibe:
            </span>
            {vibePills.map((pill) => (
              <motion.button
                key={pill.label}
                className={`px-3 py-1 rounded-full font-label-md text-label-md transition-all ${
                  pill.active
                    ? 'bg-primary text-on-primary shadow-sm'
                    : 'bg-surface-container hover:bg-surface-container-high text-on-surface'
                }`}
                type="button"
                whileHover={{ scale: 1.06, y: -1 }}
                whileTap={{ scale: 0.95 }}
                transition={{ duration: 0.15 }}
                variants={fadeUp}
              >
                {pill.label}
              </motion.button>
            ))}
          </motion.div>
        </motion.div>
      </div>
    </section>
  );
}
