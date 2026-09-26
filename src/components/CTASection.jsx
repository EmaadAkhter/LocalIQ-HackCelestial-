import { motion } from 'motion/react';
import { fadeUp, scaleIn, viewportOnce } from '../lib/animations';

export default function CTASection() {
  return (
    <section className="w-full px-5 py-space-xl bg-inverse-surface overflow-hidden relative">
      {/* Atmospheric glow */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[600px] h-[300px] bg-primary-container/20 blur-3xl pointer-events-none" />

      <div className="max-w-4xl mx-auto flex flex-col items-center gap-8 text-center relative">
        <motion.div
          className="flex flex-col items-center gap-4"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <span className="font-label-sm text-label-sm tracking-widest uppercase text-inverse-primary">
            Ready to explore?
          </span>
          <h2 className="font-[Manrope] text-[36px] md:text-[52px] leading-[1.05] tracking-[-0.04em] font-bold text-inverse-on-surface">
            MUMBAI IS WAITING.
            <br />
            <span className="font-[Newsreader] italic font-normal text-primary-fixed-dim">
              start somewhere unexpected.
            </span>
          </h2>
          <p className="font-[Newsreader] text-[18px] leading-[26px] text-inverse-on-surface/70 max-w-xl">
            Join 140+ local contributors building the most thoughtful neighborhood
            intelligence platform Mumbai has ever seen.
          </p>
        </motion.div>

        <motion.div
          className="flex flex-col sm:flex-row gap-3 items-center"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={{ ...viewportOnce, margin: '-40px' }}
        >
          <motion.button
            className="bg-primary-container text-on-primary font-label-lg text-label-lg px-10 py-4 rounded-full shadow-lg flex items-center gap-2 hover:bg-[#e44e2c] transition-colors cursor-pointer"
            whileHover={{ scale: 1.06, y: -3, boxShadow: '0 16px 36px -4px rgba(255,90,54,0.5)' }}
            whileTap={{ scale: 0.96 }}
            transition={{ duration: 0.22 }}
          >
            <span className="material-symbols-outlined text-[20px]">explore</span>
            Start exploring Mumbai
          </motion.button>
          <motion.button
            className="border border-inverse-on-surface/30 text-inverse-on-surface font-label-lg text-label-lg px-10 py-4 rounded-full hover:bg-inverse-on-surface/10 transition-colors cursor-pointer"
            whileHover={{ scale: 1.04, y: -2 }}
            whileTap={{ scale: 0.97 }}
            transition={{ duration: 0.2 }}
          >
            Become a contributor
          </motion.button>
        </motion.div>

        {/* Trust indicators */}
        <motion.div
          className="flex items-center gap-6 flex-wrap justify-center pt-4"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {[
            { icon: 'verified', label: '140+ Verified Contributors' },
            { icon: 'lock', label: 'No data sold, ever' },
            { icon: 'star', label: '4.9★ Average Rating' },
          ].map((item) => (
            <div key={item.label} className="flex items-center gap-2 text-inverse-on-surface/60">
              <span className="material-symbols-outlined text-[18px] text-primary-fixed-dim">{item.icon}</span>
              <span className="font-label-md text-label-md">{item.label}</span>
            </div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
