import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const cards = [
  {
    id: 'food-after-dark',
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

function ExperienceCard({ card, index }) {
  return (
    <motion.div
      className="flex flex-col rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm group"
      variants={scaleIn}
      whileHover={{
        y: -6,
        boxShadow: '0 20px 40px -8px rgba(46,39,36,0.15)',
        transition: { duration: 0.3, ease: [0.22, 1, 0.36, 1] },
      }}
      transition={{ duration: 0.3 }}
    >
      <div className="relative h-64 overflow-hidden">
        <motion.img
          className="w-full h-full object-cover"
          src={card.imgSrc}
          alt={card.imgAlt}
          whileHover={{ scale: 1.06 }}
          transition={{ duration: 0.7, ease: [0.22, 1, 0.36, 1] }}
        />
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
          <motion.span
            className="font-label-md text-label-md text-primary font-semibold flex items-center gap-1 cursor-pointer"
            whileHover={{ x: 3 }}
            transition={{ duration: 0.18 }}
          >
            Explore Route{' '}
            <span className="material-symbols-outlined text-[16px]">arrow_forward</span>
          </motion.span>
          <motion.span
            className="material-symbols-outlined text-on-surface-variant/40 group-hover:text-primary transition-colors cursor-pointer"
            whileHover={{ scale: 1.2 }}
            whileTap={{ scale: 0.88 }}
            transition={{ duration: 0.15 }}
          >
            bookmark
          </motion.span>
        </div>
      </div>
    </motion.div>
  );
}

export default function DiscoverySection() {
  return (
    <section className="w-full px-5 py-space-xl bg-surface-container-low">
      <div className="max-w-7xl mx-auto flex flex-col gap-6">
        {/* Section header */}
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

        {/* Cards grid */}
        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-4 items-stretch"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {cards.map((card, i) => (
            <ExperienceCard key={card.id} card={card} index={i} />
          ))}
        </motion.div>
      </div>
    </section>
  );
}
