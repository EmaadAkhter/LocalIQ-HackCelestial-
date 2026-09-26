import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { revealUp, spring } from '../lib/animations';
import { usePointerTilt } from '../lib/motionHooks';
import { rightNowLabel } from '../data/mock';
import { useLocalIQ } from '../context/LocalIQContext';

export default function ExperienceCard({ experience, compact = false }) {
  const { savedIds, toggleSave, addToPlan, planIds } = useLocalIQ();
  const saved = savedIds.includes(experience.id);
  const planned = planIds.includes(experience.id);
  const tilt = usePointerTilt({ max: 6 });

  return (
    <motion.div variants={revealUp} className="h-full" style={{ perspective: 900 }}>
      <motion.article
        {...tilt.bind}
        className="group relative flex flex-col rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm h-full"
        style={{ rotateX: tilt.rotateX, rotateY: tilt.rotateY, transformStyle: 'preserve-3d' }}
        whileHover={{ boxShadow: '0 20px 40px -8px rgba(46,39,36,0.15)' }}
        transition={spring}
      >
      <Link to={`/experience/${experience.id}`} className="relative overflow-hidden">
        <img
          src={experience.img}
          alt={experience.title}
          className={`w-full object-cover ${compact ? 'h-40' : 'h-56'} group-hover:scale-105 transition-transform duration-700`}
        />
        <div className="absolute inset-0 bg-gradient-to-t from-on-surface/50 via-transparent to-transparent" />
        <div className="absolute top-3 left-3 bg-surface-container-lowest/90 backdrop-blur-sm px-2.5 py-1 rounded-full font-label-sm text-label-sm text-on-surface flex items-center gap-1">
          <span className="material-symbols-outlined text-[14px] text-primary-container" style={{ fontVariationSettings: "'FILL' 1" }}>
            local_fire_department
          </span>
          {experience.rightNow}% · {rightNowLabel(experience.rightNow)}
        </div>
        <div className="absolute top-3 right-3 bg-surface-container-lowest/90 backdrop-blur-sm px-2.5 py-1 rounded-full font-label-sm text-label-sm font-semibold text-on-surface">
          {experience.cost === 0 ? 'Free' : experience.costLabel}
        </div>
        {experience.hiddenGem && (
          <div className="absolute bottom-3 left-3 bg-tertiary-fixed text-on-tertiary-fixed px-2.5 py-1 rounded-full font-label-sm text-label-sm">
            Hidden gem
          </div>
        )}
      </Link>

      <div className="p-4 flex flex-col gap-3 flex-1">
        <div>
          <div className="flex items-center gap-2 flex-wrap mb-1">
            <span className="bg-secondary-container text-on-secondary-container font-label-sm text-label-sm px-2 py-0.5 rounded-full">
              {experience.category}
            </span>
            <span className="font-label-sm text-label-sm text-on-surface-variant">
              {experience.neighborhood} · {experience.distanceKm} km
            </span>
          </div>
          <h3 className="font-headline-sm text-headline-sm text-on-surface">{experience.title}</h3>
          <p className="font-body-md text-body-md text-on-surface-variant line-clamp-2 mt-1">
            {experience.description}
          </p>
        </div>

        <p className="font-body-editorial-italic text-body-editorial-italic text-on-surface-variant">
          {experience.context}
        </p>

        <div className="flex items-center gap-2 mt-auto">
          <Link
            to={`/experience/${experience.id}`}
            className="flex-1 text-center rounded-xl bg-primary-container text-on-primary font-label-md text-label-md py-2.5 hover:bg-coral-hover transition-colors"
          >
            {planned ? 'In your plan' : 'Open experience'}
          </Link>
          <motion.button
            type="button"
            onClick={() => toggleSave(experience.id)}
            className="w-11 h-11 rounded-full bg-surface-container flex items-center justify-center text-on-surface-variant hover:text-primary"
            aria-label={saved ? 'Remove bookmark' : 'Save to bookmarks'}
            whileHover={{ scale: 1.12 }}
            whileTap={{ scale: 0.88 }}
            animate={saved ? { scale: [1, 1.35, 1] } : { scale: 1 }}
            transition={spring}
          >
            <span
              className="material-symbols-outlined"
              style={{ fontVariationSettings: saved ? "'FILL' 1" : "'FILL' 0", color: saved ? '#B52603' : undefined }}
            >
              bookmark
            </span>
          </motion.button>
          <button
            type="button"
            onClick={() => addToPlan(experience.id)}
            className="w-11 h-11 rounded-full bg-surface-container flex items-center justify-center text-on-surface-variant hover:text-primary"
            aria-label="Add to plan"
          >
            <span className="material-symbols-outlined">{planned ? 'check' : 'add'}</span>
          </button>
        </div>
      </div>
      {!tilt.reduce && (
        <motion.div
          className="pointer-events-none absolute inset-0 mix-blend-soft-light opacity-0 group-hover:opacity-100 transition-opacity rounded-2xl"
          style={{ background: tilt.spotlight }}
        />
      )}
    </motion.article>
    </motion.div>
  );
}
