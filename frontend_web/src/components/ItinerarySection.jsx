import { useMemo, useState } from 'react';
import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const itineraryDays = [
  {
    id: 'fort-colaba',
    day: 'Day 1',
    theme: 'Fort & Colaba',
    color: 'bg-primary-container text-on-primary',
    match: ['Heritage', 'Food', 'Art'],
    spots: [
      { id: 'horniman-circle', time: '7:30 AM', name: 'Horniman Circle Heritage Walk', type: 'Heritage', duration: '90 min' },
      { id: 'kyani', time: '9:30 AM', name: 'Filter chai at Kyani & Co.', type: 'Food', duration: '45 min' },
      { id: 'sassoon-docks', time: '11:00 AM', name: 'Sassoon Docks Art Project', type: 'Art', duration: '2 hrs' },
      { id: 'causeway', time: '2:00 PM', name: 'Colaba Causeway browse', type: 'Shopping', duration: '1 hr' },
    ],
  },
  {
    id: 'bandra-khar',
    day: 'Day 2',
    theme: 'Bandra & Khar',
    color: 'bg-tertiary-container text-on-tertiary',
    match: ['Outdoors', 'Food', 'Scenic'],
    spots: [
      { id: 'bandstand', time: '8:00 AM', name: 'Bandstand promenade walk', type: 'Outdoors', duration: '1 hr' },
      { id: 'pali-market', time: '10:00 AM', name: 'Pali Market coffee & brunch', type: 'Food', duration: '90 min' },
      { id: 'chapel-road', time: '12:30 PM', name: 'Chapel Road antique stores', type: 'Shopping', duration: '1 hr' },
      { id: 'sunset-bandra', time: '6:00 PM', name: 'Bandra Bandstand sunset', type: 'Scenic', duration: '1 hr' },
    ],
  },
  {
    id: 'dharavi-dadar',
    day: 'Day 3',
    theme: 'Dharavi & Dadar',
    color: 'bg-secondary-container text-on-secondary-container',
    match: ['Community', 'Food', 'Nature'],
    spots: [
      { id: 'dharavi-craft', time: '9:00 AM', name: 'Dharavi craft tour', type: 'Community', duration: '3 hrs' },
      { id: 'shiv-sagar', time: '1:00 PM', name: 'Shiv Sagar lunch', type: 'Food', duration: '1 hr' },
      { id: 'flower-market', time: '3:00 PM', name: 'Dadar flower market', type: 'Market', duration: '1 hr' },
      { id: 'mahim-park', time: '6:00 PM', name: 'Mahim Nature Park walk', type: 'Nature', duration: '1 hr' },
    ],
  },
];

const moodOptions = ['Foodie', 'Culture', 'Chill', 'Night Out'];

export default function ItinerarySection({ id = 'plan-a-trip' }) {
  const [selectedDayId, setSelectedDayId] = useState(itineraryDays[0].id);
  const [activeMood, setActiveMood] = useState('Foodie');
  const [savedSpots, setSavedSpots] = useState(['horniman-circle', 'pali-market']);

  const selectedDay = useMemo(
    () => itineraryDays.find((day) => day.id === selectedDayId) ?? itineraryDays[0],
    [selectedDayId]
  );

  const recommendedDay = useMemo(() => {
    const map = {
      Foodie: 'bandra-khar',
      Culture: 'fort-colaba',
      Chill: 'bandra-khar',
      'Night Out': 'fort-colaba',
    };

    return itineraryDays.find((day) => day.id === map[activeMood]) ?? itineraryDays[0];
  }, [activeMood]);

  const toggleSave = (spotId) => {
    setSavedSpots((current) =>
      current.includes(spotId)
        ? current.filter((item) => item !== spotId)
        : [...current, spotId]
    );
  };

  const generatePlan = () => {
    setSelectedDayId(recommendedDay.id);
  };

  return (
    <section id={id} className="w-full px-5 py-space-xl bg-background">
      <div className="max-w-7xl mx-auto flex flex-col gap-8">
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

        <motion.div
          className="rounded-3xl border border-outline-variant bg-surface-container-lowest p-4 md:p-5 shadow-sm"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="font-label-sm text-label-sm uppercase tracking-widest text-primary">Planner mode</p>
              <h3 className="font-headline-md text-headline-md text-on-surface mt-1">
                {activeMood} energy · {recommendedDay.theme}
              </h3>
            </div>

            <div className="flex flex-wrap gap-2">
              {moodOptions.map((mood) => (
                <button
                  key={mood}
                  type="button"
                  onClick={() => setActiveMood(mood)}
                  className={`rounded-full px-3 py-1.5 font-label-md text-label-md transition-colors ${
                    activeMood === mood
                      ? 'bg-primary-container text-on-primary'
                      : 'bg-surface-container text-on-surface-variant hover:bg-surface-container-high'
                  }`}
                >
                  {mood}
                </button>
              ))}
            </div>
          </div>
        </motion.div>

        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-5"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {itineraryDays.map((day) => {
            const isSelected = selectedDay.id === day.id;

            return (
              <motion.button
                key={day.id}
                type="button"
                onClick={() => setSelectedDayId(day.id)}
                className={`text-left rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm transition-all ${
                  isSelected ? 'ring-2 ring-primary ring-offset-2 ring-offset-background' : ''
                }`}
                variants={scaleIn}
                whileHover={{ y: -4, boxShadow: '0 12px 28px -6px rgba(46,39,36,0.12)', transition: { duration: 0.28 } }}
              >
                <div className={`p-4 ${day.color}`}>
                  <div className="font-label-sm text-label-sm uppercase tracking-widest opacity-80">{day.day}</div>
                  <div className="font-headline-sm text-headline-sm mt-0.5">{day.theme}</div>
                </div>

                <div className="p-4 flex flex-col gap-3">
                  {day.spots.map((spot, si) => {
                    const isSaved = savedSpots.includes(spot.id);

                    return (
                      <div key={spot.id} className="flex gap-3 items-start group">
                        <div className="flex flex-col items-center gap-1 shrink-0 pt-0.5">
                          <div className="w-2 h-2 rounded-full bg-primary-container" />
                          {si < day.spots.length - 1 && <div className="w-0.5 h-6 bg-outline-variant" />}
                        </div>

                        <div className="flex flex-col gap-0.5 flex-1 min-w-0">
                          <div className="flex items-center justify-between gap-2">
                            <span className="font-[JetBrains_Mono,monospace] text-[11px] text-on-surface-variant font-medium tracking-[0.02em]">
                              {spot.time}
                            </span>
                            <span className="font-label-sm text-label-sm text-on-surface-variant">{spot.duration}</span>
                          </div>

                          <div className="flex items-start justify-between gap-2">
                            <span className="font-label-lg text-label-lg text-on-surface group-hover:text-primary transition-colors font-semibold text-left">
                              {spot.name}
                            </span>
                            <button
                              type="button"
                              onClick={(event) => {
                                event.stopPropagation();
                                toggleSave(spot.id);
                              }}
                              className="material-symbols-outlined text-[18px] shrink-0 transition-colors"
                              style={{ color: isSaved ? '#B52603' : 'rgba(91,64,58,0.45)' }}
                              aria-label={isSaved ? 'Remove spot from saved plan' : 'Save spot to plan'}
                            >
                              {isSaved ? 'bookmark_added' : 'bookmark'}
                            </button>
                          </div>

                          <span className="font-label-sm text-label-sm text-on-surface-variant/70">{spot.type}</span>
                        </div>
                      </div>
                    );
                  })}
                </div>

                <div className="px-4 pb-4">
                  <span className="w-full py-2.5 rounded-xl bg-surface-container text-on-surface font-label-md text-label-md flex items-center justify-center gap-1.5">
                    <span className="material-symbols-outlined text-[16px]">add</span>
                    {isSelected ? 'Selected plan' : 'Add to my plan'}
                  </span>
                </div>
              </motion.button>
            );
          })}
        </motion.div>

        <motion.div
          className="rounded-3xl border border-outline-variant bg-surface-container-lowest p-5 shadow-sm"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <div>
              <p className="font-label-sm text-label-sm uppercase tracking-widest text-primary">Current selection</p>
              <h3 className="font-headline-md text-headline-md text-on-surface mt-1">{selectedDay.day} · {selectedDay.theme}</h3>
            </div>

            <div className="flex items-center gap-2 text-on-surface-variant font-body-md">
              <span className="material-symbols-outlined text-[18px]">schedule</span>
              <span>{selectedDay.spots.length} activities planned</span>
            </div>
          </div>

          <div className="mt-4 flex flex-wrap gap-2">
            {selectedDay.match.map((tag) => (
              <span key={tag} className="rounded-full bg-surface-container px-3 py-1 font-label-sm text-label-sm text-on-surface-variant">
                {tag}
              </span>
            ))}
          </div>
        </motion.div>

        <motion.div
          className="flex flex-col sm:flex-row gap-3 justify-center items-center"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <motion.button
            type="button"
            onClick={generatePlan}
            className="bg-primary-container hover:bg-primary text-on-primary font-label-lg text-label-lg px-8 py-4 rounded-full shadow-lg flex items-center gap-2 transition-colors cursor-pointer"
            whileHover={{ scale: 1.04, y: -2, boxShadow: '0 12px 28px -4px rgba(255,90,54,0.4)' }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.22 }}
          >
            <span className="material-symbols-outlined text-[20px]">auto_fix_high</span>
            Generate my {recommendedDay.theme} itinerary
          </motion.button>
          <motion.a
            href="#discover"
            className="border border-outline-variant text-on-surface font-label-lg text-label-lg px-8 py-4 rounded-full flex items-center gap-2 hover:bg-surface-container transition-colors cursor-pointer"
            whileHover={{ scale: 1.03, y: -1 }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.2 }}
          >
            <span className="material-symbols-outlined text-[20px]">share</span>
            Share this plan
          </motion.a>
        </motion.div>
      </div>
    </section>
  );
}
