import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const steps = [
  {
    step: '01',
    icon: 'psychology',
    title: 'Tell us your vibe',
    description:
      'Speak plainly — "something slow near a sea view" or "heritage walk before sunset." Our AI understands how Mumbai moods are formed.',
  },
  {
    step: '02',
    icon: 'auto_fix_high',
    title: 'We decode the city',
    description:
      'Cross-referencing 140+ local contributors, real-time crowd data, transit lines, and hidden neighborhood knowledge banks.',
  },
  {
    step: '03',
    icon: 'route',
    title: 'Your moment, your route',
    description:
      `A curated day or evening arc — timed to the city's rhythms, not a generic checklist. Adjust, save, or share with a single tap.`,
  },
];

const statItems = [
  { value: '140+', label: 'Local contributors', icon: 'groups' },
  { value: '600+', label: 'Curated experiences', icon: 'explore' },
  { value: '24', label: 'Neighborhoods mapped', icon: 'map' },
  { value: '4.9★', label: 'Average experience rating', icon: 'star' },
];

export default function HowItWorksSection() {
  return (
    <section className="w-full px-5 py-space-xl bg-surface-container-low">
      <div className="max-w-7xl mx-auto flex flex-col gap-10">
        {/* Header */}
        <motion.div
          className="flex flex-col gap-2 max-w-2xl"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <span className="font-label-sm text-label-sm tracking-widest uppercase text-primary font-bold">
            How it works
          </span>
          <h2 className="font-[Manrope] text-[28px] md:text-[36px] leading-[1.1] tracking-[-0.03em] font-bold text-on-surface">
            INTELLIGENT BY DESIGN.
            <br />
            <span className="font-[Newsreader] italic font-normal text-on-surface-variant">
              human at heart.
            </span>
          </h2>
          <p className="font-body-md text-body-md text-on-surface-variant mt-2">
            Not another algorithm chasing your clicks. LocalIQ reads the texture of the city
            — the time, the mood, the hidden rhythm — and maps it to you.
          </p>
        </motion.div>

        {/* Steps */}
        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-6"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {steps.map((step, i) => (
            <motion.div
              key={step.step}
              className="relative flex flex-col gap-4 p-6 rounded-2xl bg-surface-container-lowest shadow-sm group"
              variants={scaleIn}
              whileHover={{
                y: -4,
                boxShadow: '0 12px 28px -6px rgba(46,39,36,0.12)',
                transition: { duration: 0.28 },
              }}
            >
              {/* Step connector line (desktop) */}
              {i < steps.length - 1 && (
                <div className="hidden md:block absolute top-10 -right-3 w-6 h-0.5 bg-outline-variant z-10" />
              )}
              <div className="flex items-center gap-3">
                <motion.div
                  className="w-12 h-12 rounded-2xl bg-primary-container/10 flex items-center justify-center text-primary"
                  whileHover={{ scale: 1.1, backgroundColor: 'rgba(255,90,54,0.15)' }}
                  transition={{ duration: 0.22 }}
                >
                  <span className="material-symbols-outlined text-[24px]">{step.icon}</span>
                </motion.div>
                <span className="font-[JetBrains_Mono,monospace] text-[11px] font-bold tracking-[0.08em] text-on-surface-variant uppercase">
                  Step {step.step}
                </span>
              </div>
              <h3 className="font-headline-sm text-headline-sm text-on-surface group-hover:text-primary transition-colors">
                {step.title}
              </h3>
              <p className="font-body-md text-body-md text-on-surface-variant">{step.description}</p>
            </motion.div>
          ))}
        </motion.div>

        {/* Stats row */}
        <motion.div
          className="grid grid-cols-2 lg:grid-cols-4 gap-4 mt-4"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {statItems.map((stat) => (
            <motion.div
              key={stat.label}
              className="flex flex-col items-center gap-2 p-5 rounded-2xl bg-surface-container-lowest text-center shadow-sm"
              variants={fadeUp}
              whileHover={{ y: -3, transition: { duration: 0.2 } }}
            >
              <span className="material-symbols-outlined text-primary text-[24px]">{stat.icon}</span>
              <span className="font-[Manrope] text-[28px] font-bold tracking-[-0.03em] text-on-surface">
                {stat.value}
              </span>
              <span className="font-label-md text-label-md text-on-surface-variant">
                {stat.label}
              </span>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
