import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const itineraryDays = [
  {
    day: 'Day 1',
    theme: 'Fort & Colaba',
    color: 'bg-primary-container text-on-primary',
    spots: [
      { time: '7:30 AM', name: 'Horniman Circle Heritage Walk', type: 'Heritage', duration: '90 min' },
      { time: '9:30 AM', name: 'Filter chai at Kyani & Co.', type: 'Food', duration: '45 min' },
      { time: '11:00 AM', name: 'Sassoon Docks Art Project', type: 'Art', duration: '2 hrs' },
      { time: '2:00 PM', name: 'Colaba Causeway browse', type: 'Shopping', duration: '1 hr' },
    ],
  },
  {
    day: 'Day 2',
    theme: 'Bandra & Khar',
    color: 'bg-tertiary-container text-on-tertiary',
    spots: [
      { time: '8:00 AM', name: 'Bandstand promenade walk', type: 'Outdoors', duration: '1 hr' },
      { time: '10:00 AM', name: 'Pali Market coffee & brunch', type: 'Food', duration: '90 min' },
      { time: '12:30 PM', name: 'Chapel Road antique stores', type: 'Shopping', duration: '1 hr' },
      { time: '6:00 PM', name: 'Bandra Bandstand sunset', type: 'Scenic', duration: '1 hr' },
    ],
  },
  {
    day: 'Day 3',
    theme: 'Dharavi & Dadar',
    color: 'bg-secondary-container text-on-secondary-container',
    spots: [
      { time: '9:00 AM', name: 'Dharavi craft tour', type: 'Community', duration: '3 hrs' },
      { time: '1:00 PM', name: 'Shiv Sagar lunch', type: 'Food', duration: '1 hr' },
      { time: '3:00 PM', name: 'Dadar flower market', type: 'Market', duration: '1 hr' },
      { time: '6:00 PM', name: 'Mahim Nature Park walk', type: 'Nature', duration: '1 hr' },
    ],
  },
];

export default function ItinerarySection() {
  return (
    <section className="w-full px-5 py-space-xl bg-background">
      <div className="max-w-7xl mx-auto flex flex-col gap-8">
        {/* Header */}
        <motion.div
          className="flex flex-col gap-2"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <span className="font-label-sm text-label-sm tracking-widest uppercase text-primary font-bold">
            3-Day Mumbai Arc
          </span>
          <h2 className="font-[Manrope] text-[28px] md:text-[36px] leading-[1.1] tracking-[-0.03em] font-bold text-on-surface">
            YOUR CURATED ITINERARY
            <br />
            <span className="font-[Newsreader] italic font-normal text-on-surface-variant">
              shaped around how you move.
            </span>
          </h2>
        </motion.div>

        {/* 3 day columns */}
        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-5"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {itineraryDays.map((day, di) => (
            <motion.div
              key={day.day}
              className="rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm"
              variants={scaleIn}
              whileHover={{ y: -4, boxShadow: '0 12px 28px -6px rgba(46,39,36,0.12)', transition: { duration: 0.28 } }}
            >
              {/* Day header */}
              <div className={`p-4 ${day.color}`}>
                <div className="font-label-sm text-label-sm uppercase tracking-widest opacity-80">{day.day}</div>
                <div className="font-headline-sm text-headline-sm mt-0.5">{day.theme}</div>
              </div>

              {/* Spots list */}
              <div className="p-4 flex flex-col gap-3">
                {day.spots.map((spot, si) => (
                  <motion.div
                    key={spot.name}
                    className="flex gap-3 items-start group cursor-pointer"
                    whileHover={{ x: 4 }}
                    transition={{ duration: 0.18 }}
                  >
                    <div className="flex flex-col items-center gap-1 shrink-0 pt-0.5">
                      <div className="w-2 h-2 rounded-full bg-primary-container" />
                      {si < day.spots.length - 1 && (
                        <div className="w-0.5 h-6 bg-outline-variant" />
                      )}
                    </div>
                    <div className="flex flex-col gap-0.5 flex-1">
                      <div className="flex items-center justify-between">
                        <span className="font-[JetBrains_Mono,monospace] text-[11px] text-on-surface-variant font-medium tracking-[0.02em]">
                          {spot.time}
                        </span>
                        <span className="font-label-sm text-label-sm text-on-surface-variant">
                          {spot.duration}
                        </span>
                      </div>
                      <span className="font-label-lg text-label-lg text-on-surface group-hover:text-primary transition-colors font-semibold">
                        {spot.name}
                      </span>
                      <span className="font-label-sm text-label-sm text-on-surface-variant/70">
                        {spot.type}
                      </span>
                    </div>
                  </motion.div>
                ))}
              </div>

              {/* CTA */}
              <div className="px-4 pb-4">
                <motion.button
                  className="w-full py-2.5 rounded-xl bg-surface-container text-on-surface font-label-md text-label-md flex items-center justify-center gap-1.5 hover:bg-primary-container hover:text-on-primary transition-colors"
                  whileTap={{ scale: 0.97 }}
                  transition={{ duration: 0.15 }}
                >
                  <span className="material-symbols-outlined text-[16px]">add</span>
                  Add to my plan
                </motion.button>
              </div>
            </motion.div>
          ))}
        </motion.div>

        {/* Generate CTA */}
        <motion.div
          className="flex flex-col sm:flex-row gap-3 justify-center items-center"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <motion.button
            className="bg-primary-container hover:bg-primary text-on-primary font-label-lg text-label-lg px-8 py-4 rounded-full shadow-lg flex items-center gap-2 transition-colors cursor-pointer"
            whileHover={{ scale: 1.04, y: -2, boxShadow: '0 12px 28px -4px rgba(255,90,54,0.4)' }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.22 }}
          >
            <span className="material-symbols-outlined text-[20px]">auto_fix_high</span>
            Generate my Mumbai itinerary
          </motion.button>
          <motion.button
            className="border border-outline-variant text-on-surface font-label-lg text-label-lg px-8 py-4 rounded-full flex items-center gap-2 hover:bg-surface-container transition-colors cursor-pointer"
            whileHover={{ scale: 1.03, y: -1 }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.2 }}
          >
            <span className="material-symbols-outlined text-[20px]">share</span>
            Share this plan
          </motion.button>
        </motion.div>
      </div>
    </section>
  );
}
