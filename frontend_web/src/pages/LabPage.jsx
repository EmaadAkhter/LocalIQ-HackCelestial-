import { useRef } from 'react';
import { motion, useMotionValue, useScroll, useSpring, useTransform } from 'motion/react';
import { usePointerTilt } from '../lib/motionHooks';

/* ------------------------------------------------------------------ *
 * LocalIQ Motion Lab — candidate "extravagant" treatments.
 * All built on the existing `motion` lib + Material-3 tokens.
 * No new dependencies, so nothing here clashes with the theme.
 * Not linked in nav — review-only at /lab.
 * ------------------------------------------------------------------ */

function LabSection({ n, title, note, children }) {
  return (
    <section className="border-t border-outline-variant/40 py-16">
      <div className="max-w-6xl mx-auto px-5">
        <div className="mb-8 flex items-baseline gap-3">
          <span className="font-[JetBrains_Mono,monospace] text-[12px] text-primary">{n}</span>
          <div>
            <h2 className="font-[Manrope] text-[26px] font-bold tracking-[-0.02em] text-on-surface">{title}</h2>
            <p className="font-body-md text-body-md text-on-surface-variant mt-1 max-w-xl">{note}</p>
          </div>
        </div>
        {children}
      </div>
    </section>
  );
}

/* 1 — Aurora hero: drifting coral light behind editorial type. */
function AuroraHero() {
  return (
    <div className="relative h-[380px] rounded-3xl overflow-hidden bg-inverse-surface flex items-center justify-center">
      <motion.div
        className="absolute -inset-1/2 opacity-70"
        style={{
          background:
            'conic-gradient(from 0deg, #FF5A36, #b52603, #fff8f6, #FF5A36)',
          filter: 'blur(80px)',
        }}
        animate={{ rotate: 360 }}
        transition={{ repeat: Infinity, duration: 22, ease: 'linear' }}
      />
      <div className="absolute inset-0 bg-inverse-surface/40" />
      <div className="relative text-center px-6">
        <p className="font-label-sm text-label-sm uppercase tracking-[0.2em] text-primary-fixed-dim">Golden hour, live</p>
        <h3 className="font-[Manrope] text-[44px] md:text-[64px] font-bold tracking-[-0.04em] text-inverse-on-surface leading-[0.95]">
          The city is glowing.
        </h3>
        <p className="font-[Newsreader] italic text-[20px] text-inverse-on-surface/70 mt-2">Find your window before it closes.</p>
      </div>
    </div>
  );
}

/* 2 — Scroll word-reveal: paragraph brightens word-by-word as you scroll. */
function WordReveal() {
  const ref = useRef(null);
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start 0.85', 'start 0.25'] });
  const text =
    'Not another algorithm chasing your clicks. LocalIQ reads the texture of the city — the time, the mood, the hidden rhythm — and maps it to you.';
  const words = text.split(' ');
  return (
    <p ref={ref} className="font-[Manrope] text-[28px] md:text-[38px] font-semibold leading-[1.3] tracking-[-0.02em] flex flex-wrap gap-x-2.5">
      {words.map((word, i) => {
        const start = i / words.length;
        const end = start + 1 / words.length;
        return <RevealWord key={i} progress={scrollYProgress} range={[start, end]} word={word} />;
      })}
    </p>
  );
}

function RevealWord({ progress, range, word }) {
  const opacity = useTransform(progress, range, [0.18, 1]);
  const color = useTransform(progress, range, ['#5b403a', '#b52603']);
  return (
    <motion.span style={{ opacity, color }} className="text-on-surface">
      {word}
    </motion.span>
  );
}

/* 3 — Glow-border spotlight card: rotating conic edge + cursor tilt. */
function GlowCard({ title, meta }) {
  const tilt = usePointerTilt({ max: 8 });
  return (
    <motion.div style={{ perspective: 900 }}>
      <motion.div
        {...tilt.bind}
        className="relative rounded-2xl p-[1.5px] overflow-hidden"
        style={{ rotateX: tilt.rotateX, rotateY: tilt.rotateY, transformStyle: 'preserve-3d' }}
      >
        <motion.div
          className="absolute -inset-8 opacity-0 group-hover:opacity-100"
          style={{ background: 'conic-gradient(from 0deg, transparent, #FF5A36, transparent 40%)' }}
          animate={{ rotate: 360 }}
          transition={{ repeat: Infinity, duration: 6, ease: 'linear' }}
        />
        <div className="relative rounded-[15px] bg-surface-container-lowest p-5 h-44 flex flex-col justify-between">
          <span className="material-symbols-outlined text-primary">explore</span>
          <div>
            <h4 className="font-headline-sm text-headline-sm text-on-surface">{title}</h4>
            <p className="font-label-sm text-label-sm text-on-surface-variant">{meta}</p>
          </div>
        </div>
      </motion.div>
    </motion.div>
  );
}

/* 4 — Neighborhood marquee: two rows ticking in opposite directions. */
function MarqueeRow({ items, dir }) {
  return (
    <div className="flex overflow-hidden">
      <motion.div
        className="flex gap-3 shrink-0 pr-3"
        animate={{ x: dir > 0 ? ['-50%', '0%'] : ['0%', '-50%'] }}
        transition={{ repeat: Infinity, duration: 26, ease: 'linear' }}
      >
        {[...items, ...items].map((n, i) => (
          <span key={i} className="whitespace-nowrap rounded-full bg-surface-container px-4 py-2 font-label-md text-on-surface">
            {n}
          </span>
        ))}
      </motion.div>
    </div>
  );
}

function Marquee() {
  const rowA = ['Bandra', 'Colaba', 'Fort', 'Worli Koliwada', 'Kala Ghoda', 'Bohri Mohalla', 'Dadar', 'Byculla'];
  const rowB = ['Sassoon Docks', 'Horniman Circle', 'Khau Galli', 'Marine Drive', 'Chor Bazaar', 'Matunga', 'Bandstand'];
  return (
    <div className="flex flex-col gap-3">
      <MarqueeRow items={rowA} dir={-1} />
      <MarqueeRow items={rowB} dir={1} />
    </div>
  );
}

/* 5 — Bento grid: asymmetric feature tiles. */
function Bento() {
  return (
    <div className="grid grid-cols-2 md:grid-cols-4 auto-rows-[130px] gap-3">
      <div className="col-span-2 row-span-2 rounded-2xl bg-primary-container text-on-primary p-5 flex flex-col justify-between">
        <span className="material-symbols-outlined text-[28px]">auto_awesome</span>
        <div>
          <h4 className="font-[Manrope] text-[24px] font-bold leading-tight">Right now, near you</h4>
          <p className="font-body-md opacity-80">Feasible for this hour and this weather.</p>
        </div>
      </div>
      <div className="rounded-2xl bg-surface-container-lowest p-4 flex flex-col justify-between shadow-sm">
        <span className="material-symbols-outlined text-primary">route</span>
        <p className="font-label-md text-on-surface">2-hr food walk</p>
      </div>
      <div className="rounded-2xl bg-tertiary text-on-tertiary p-4 flex flex-col justify-between">
        <span className="material-symbols-outlined">diamond</span>
        <p className="font-label-md">Hidden gems</p>
      </div>
      <div className="col-span-2 rounded-2xl bg-inverse-surface text-inverse-on-surface p-4 flex items-end">
        <p className="font-[Newsreader] italic text-[18px]">"The lane between the sea wall and the fort."</p>
      </div>
    </div>
  );
}

/* 6 — Magnetic CTA: the button leans toward your cursor. */
function MagneticButton() {
  const ref = useRef(null);
  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  const x = useSpring(mx, { stiffness: 200, damping: 15 });
  const y = useSpring(my, { stiffness: 200, damping: 15 });
  const onMove = (e) => {
    const r = ref.current?.getBoundingClientRect();
    if (!r) return;
    mx.set((e.clientX - (r.left + r.width / 2)) * 0.4);
    my.set((e.clientY - (r.top + r.height / 2)) * 0.4);
  };
  const reset = () => {
    mx.set(0);
    my.set(0);
  };
  return (
    <motion.button
      ref={ref}
      onPointerMove={onMove}
      onPointerLeave={reset}
      style={{ x, y }}
      whileTap={{ scale: 0.95 }}
      className="bg-primary-container text-on-primary font-label-lg px-8 py-4 rounded-full shadow-lg flex items-center gap-2"
    >
      <span className="material-symbols-outlined text-[20px]">explore</span>
      Start exploring
    </motion.button>
  );
}

export default function LabPage() {
  return (
    <div className="pb-24">
      <header className="max-w-6xl mx-auto px-5 pt-10 pb-6">
        <h1 className="font-[Manrope] text-[34px] font-bold tracking-[-0.03em] text-on-surface">Motion Lab</h1>
        <p className="font-body-md text-body-md text-on-surface-variant mt-1">
          Candidate extravagant treatments, all in your palette. Tell me which to roll site-wide.
        </p>
      </header>

      <LabSection n="01" title="Aurora hero" note="Drifting coral light behind editorial type. Reads as premium without a stock template. Calms fully under reduced-motion.">
        <AuroraHero />
      </LabSection>
      {/* PLACEHOLDER_SECTIONS */}
      <LabSection n="02" title="Scroll word-reveal" note="A line ignites word-by-word as it enters view — draws the eye without moving the layout. Scroll slowly to see it.">
        <WordReveal />
      </LabSection>

      <LabSection n="03" title="Glow-border cards" note="A rotating light traces the edge on hover, plus the cursor tilt you already have. Hover a card.">
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 group">
          <GlowCard title="Bandra Bandstand" meta="6:15 PM · sea-facing" />
          <GlowCard title="Kala Ghoda arts" meta="covered arcades" />
          <GlowCard title="Bohri Mohalla" meta="8:30 PM · food" />
        </div>
      </LabSection>

      <LabSection n="04" title="Neighborhood marquee" note="An ambient ticker of the places you cover. Good as a quiet band between sections.">
        <Marquee />
      </LabSection>

      <LabSection n="05" title="Bento grid" note="Asymmetric tiles for a features or 'what you get' block — more editorial than a row of equal cards.">
        <Bento />
      </LabSection>

      <LabSection n="06" title="Magnetic button" note="The primary CTA leans toward the cursor and springs back. A small, tactile flourish. Hover it.">
        <MagneticButton />
      </LabSection>
    </div>
  );
}
