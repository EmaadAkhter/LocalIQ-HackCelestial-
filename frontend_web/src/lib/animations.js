/**
 * LocalIQ — Reusable Motion Animation Variants
 * Respects prefers-reduced-motion via CSS & Motion's `useReducedMotion`
 */

export const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] },
  },
};

export const fadeIn = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { duration: 0.5, ease: 'easeOut' },
  },
};

export const scaleIn = {
  hidden: { opacity: 0, scale: 0.92 },
  visible: {
    opacity: 1,
    scale: 1,
    transition: { duration: 0.5, ease: [0.22, 1, 0.36, 1] },
  },
};

export const staggerContainer = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.1,
      delayChildren: 0.05,
    },
  },
};

export const staggerContainerFast = {
  hidden: {},
  visible: {
    transition: {
      staggerChildren: 0.07,
      delayChildren: 0.0,
    },
  },
};

export const heroTitle = {
  hidden: { opacity: 0, y: 40 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.9, ease: [0.22, 1, 0.36, 1] },
  },
};

export const heroSubtitle = {
  hidden: { opacity: 0, y: 24 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.7, ease: [0.22, 1, 0.36, 1], delay: 0.15 },
  },
};

export const heroCTA = {
  hidden: { opacity: 0, y: 16 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1], delay: 0.3 },
  },
};

export const heroImage = {
  hidden: { opacity: 0, scale: 1.04, y: 12 },
  visible: {
    opacity: 1,
    scale: 1,
    y: 0,
    transition: { duration: 1.0, ease: [0.22, 1, 0.36, 1], delay: 0.2 },
  },
};

export const slideInLeft = {
  hidden: { opacity: 0, x: -32 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] },
  },
};

export const slideInRight = {
  hidden: { opacity: 0, x: 32 },
  visible: {
    opacity: 1,
    x: 0,
    transition: { duration: 0.6, ease: [0.22, 1, 0.36, 1] },
  },
};

// Shared viewport config for whileInView
export const viewportOnce = { once: true, margin: '-80px' };

/* ───────────────────────────────────────────────
   SPRING PRESETS
   The physical language for user-triggered motion:
   presses, tilts, sliding indicators, drawers.
─────────────────────────────────────────────── */
export const spring = { type: 'spring', stiffness: 380, damping: 30, mass: 0.8 };
export const springSoft = { type: 'spring', stiffness: 180, damping: 22 };
export const springSnappy = { type: 'spring', stiffness: 500, damping: 32 };

// Per-line masked rise used by the hero headline. Parent staggers children.
export const lineRise = {
  hidden: { y: '110%' },
  visible: {
    y: '0%',
    transition: { type: 'spring', stiffness: 220, damping: 28, mass: 0.9 },
  },
};

// Quieter section reveal — small lift, one time, no theatrics.
export const revealUp = {
  hidden: { opacity: 0, y: 14 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.5, ease: [0.22, 1, 0.36, 1] },
  },
};
