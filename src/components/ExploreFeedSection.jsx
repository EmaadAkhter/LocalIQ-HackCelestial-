import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, slideInLeft, slideInRight, viewportOnce } from '../lib/animations';

const quickPicks = [
  { icon: 'edit_calendar', label: 'Plan trip' },
  { icon: 'diamond', label: 'Hidden gems' },
  { icon: 'casino', label: 'Surprise me' },
  { icon: 'near_me', label: 'Near me' },
];

const trendingItems = [
  {
    id: 't1',
    tag: 'Trending Tonight',
    tagColor: 'bg-primary-container text-on-primary',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCz20I1rra3ZkCqOKxlpIfGlhpQjxVsPmo7E5ygxUCPr_ZS6DZgtvoiTiFsqAq0LRhyfYeocNJFacAR6YTjEkT-XQ_XUZgeTQ9M5EymdDFv3Yht7Ad5iV05W_kmedsG4fDbIniQ1HxnsGKN2ef-fZ3Ine7DPMxTtDg7OaDfR3hGy9_QSeMNqzHFu8WPOHx8y58i1c_YZj8RPKDtni9hIrIh3HjIRIrha_TlBa7Dio8-piSWt9IFVrVzNQ',
    title: 'Khau Galli Night Trail',
    meta: 'Bohri Mohalla · 8:30 PM',
    match: '96',
    matchBg: 'bg-tertiary text-on-tertiary',
  },
  {
    id: 't2',
    tag: 'Hidden Gem',
    tagColor: 'bg-secondary-container text-on-secondary-container',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuDolZZnCfsE9AaK-o3WgIomzGixbZ2iADivujy9YtsTXDD8vBpjkUJZuugSjvnusEFn-qGL0gfztBliib7v1m8b788EQKp95iWPhDyqXXvAtQiVuA7W6NnjQefq8FoyFrYqnedwNpaDL0_fl3MfHbwnz2psISlEIgliY95-UjCwlZkSFbyF5xGHOUGeAGcQPbKlVoBnKsWAOnxUspX66WFibg1pq8hm6YknNMsyX3p-5CEPpEjEwCREjA',
    title: 'Sassoon Docks Mural Walk',
    meta: 'Colaba · Free · Open Now',
    match: '92',
    matchBg: 'bg-primary text-on-primary',
  },
  {
    id: 't3',
    tag: 'Community Pick',
    tagColor: 'bg-tertiary-fixed text-on-tertiary-fixed',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCiasWkb3umfWgDxgA-rJ6t-xb5bmfBMWyfeEb1j-F4cfbYKYrWjArGOzN7t7QVEOnqrxQFOI1ZhpQq3jF9NeD5ZfdCKZLi3TR30SgEscSpOdR2Cq08ph3dNR-DBFFxbXvGkrv-4x1qi5rnw-Q5L9MUTaYCEkM1eABA6MYd9jZ1E3WMuBOizUXxd5wyTC0kzFVhh4LfHtAw5vu5_vwNid3cGeZlEHxNc2Xyu2cPkyDg7qBaI3s5JT6V-w',
    title: 'Bandra Bandstand Sunset',
    meta: 'Bandra West · 6:00 PM',
    match: '89',
    matchBg: 'bg-tertiary text-on-tertiary',
  },
  {
    id: 't4',
    tag: 'Architect Approved',
    tagColor: 'bg-primary-fixed text-on-primary-fixed',
    imgSrc: 'https://lh3.googleusercontent.com/aida-public/AB6AXuCz20I1rra3ZkCqOKxlpIfGlhpQjxVsPmo7E5ygxUCPr_ZS6DZgtvoiTiFsqAq0LRhyfYeocNJFacAR6YTjEkT-XQ_XUZgeTQ9M5EymdDFv3Yht7Ad5iV05W_kmedsG4fDbIniQ1HxnsGKN2ef-fZ3Ine7DPMxTtDg7OaDfR3hGy9_QSeMNqzHFu8WPOHx8y58i1c_YZj8RPKDtni9hIrIh3HjIRIrha_TlBa7Dio8-piSWt9IFVrVzNQ',
    title: 'Horniman Circle Heritage Walk',
    meta: 'Fort · 7:00 AM',
    match: '85',
    matchBg: 'bg-secondary text-on-secondary',
  },
];

export default function ExploreFeedSection() {
  return (
    <section className="w-full px-5 py-space-xl bg-background">
      <div className="max-w-7xl mx-auto flex flex-col gap-8">
        {/* Quick picks row */}
        <motion.div
          className="flex flex-col gap-4"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <h2 className="font-headline-md text-headline-md text-on-surface">Quick picks</h2>
          <motion.div
            className="grid grid-cols-4 gap-3"
            variants={staggerContainer}
            initial="hidden"
            whileInView="visible"
            viewport={viewportOnce}
          >
            {quickPicks.map((pick) => (
              <motion.button
                key={pick.icon}
                className="flex flex-col items-center gap-2 py-3 group"
                type="button"
                variants={scaleIn}
                whileHover={{ y: -4 }}
                whileTap={{ scale: 0.91 }}
                transition={{ duration: 0.2 }}
              >
                <motion.div
                  className="w-14 h-14 rounded-2xl bg-surface-container flex items-center justify-center text-primary shadow-sm"
                  whileHover={{ backgroundColor: '#FF5A36', color: '#ffffff' }}
                  transition={{ duration: 0.22 }}
                >
                  <span className="material-symbols-outlined text-[26px]">{pick.icon}</span>
                </motion.div>
                <span className="font-label-sm text-label-sm text-on-surface text-center">
                  {pick.label}
                </span>
              </motion.button>
            ))}
          </motion.div>
        </motion.div>

        {/* Section header */}
        <motion.div
          className="flex items-baseline justify-between"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div>
            <span className="font-label-sm text-label-sm tracking-widest uppercase text-primary font-bold">
              Explore Feed
            </span>
            <h2 className="font-headline-lg text-headline-lg text-on-surface mt-1">
              Mumbai right now
            </h2>
            <p className="font-[Newsreader] text-[15px] italic leading-[22px] text-on-surface-variant mt-0.5">
              What's happening across neighborhoods
            </p>
          </div>
          <motion.a
            href="#"
            className="font-label-md text-label-md text-primary font-semibold flex items-center gap-1"
            whileHover={{ x: 3 }}
            transition={{ duration: 0.18 }}
          >
            See all <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
          </motion.a>
        </motion.div>

        {/* Trending grid */}
        <motion.div
          className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {trendingItems.map((item) => (
            <motion.div
              key={item.id}
              className="rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm group cursor-pointer"
              variants={scaleIn}
              whileHover={{
                y: -6,
                boxShadow: '0 16px 32px -6px rgba(46,39,36,0.14)',
                transition: { duration: 0.28, ease: [0.22, 1, 0.36, 1] },
              }}
            >
              <div className="relative h-44 overflow-hidden">
                <motion.img
                  className="w-full h-full object-cover"
                  src={item.imgSrc}
                  alt={item.title}
                  whileHover={{ scale: 1.08 }}
                  transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
                />
                <div className={`absolute top-3 left-3 px-2.5 py-1 rounded-full font-label-sm text-label-sm ${item.tagColor}`}>
                  {item.tag}
                </div>
                <div className={`absolute top-3 right-3 px-2.5 py-1 rounded-full font-label-sm text-label-sm font-bold ${item.matchBg}`}>
                  {item.match}%
                </div>
              </div>
              <div className="p-3 flex flex-col gap-1">
                <h3 className="font-headline-sm text-headline-sm text-on-surface group-hover:text-primary transition-colors text-[16px]">
                  {item.title}
                </h3>
                <p className="font-label-md text-label-md text-on-surface-variant">{item.meta}</p>
              </div>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
