/**
 * LocalIQ — Reduced-motion-aware motion hooks.
 * Every hook no-ops cleanly when the user prefers reduced motion, so
 * effects can be dropped in without guarding at each call site.
 */
import { useEffect, useRef, useState } from 'react';
import {
  useInView,
  useMotionValue,
  useReducedMotion,
  useSpring,
  useTransform,
} from 'motion/react';

/**
 * Cursor-reactive 3D tilt + spotlight for a card-like element.
 * Spread `bind` onto the element and drive a `motion` element's `style`
 * with the returned motion values (rotateX / rotateY, and the spotlight
 * background). Falls back to no movement under reduced motion.
 */
export function usePointerTilt({ max = 7 } = {}) {
  const reduce = useReducedMotion();
  const ref = useRef(null);

  const px = useMotionValue(0.5);
  const py = useMotionValue(0.5);
  const sx = useSpring(px, { stiffness: 220, damping: 22, mass: 0.6 });
  const sy = useSpring(py, { stiffness: 220, damping: 22, mass: 0.6 });

  const rotateX = useTransform(sy, [0, 1], [max, -max]);
  const rotateY = useTransform(sx, [0, 1], [-max, max]);
  const spotlight = useTransform(
    [sx, sy],
    ([x, y]) =>
      `radial-gradient(220px circle at ${x * 100}% ${y * 100}%, rgba(255,255,255,0.28), transparent 65%)`,
  );

  const onPointerMove = (event) => {
    if (reduce) return;
    const rect = ref.current?.getBoundingClientRect();
    if (!rect) return;
    px.set((event.clientX - rect.left) / rect.width);
    py.set((event.clientY - rect.top) / rect.height);
  };

  const reset = () => {
    px.set(0.5);
    py.set(0.5);
  };

  return {
    reduce,
    rotateX,
    rotateY,
    spotlight,
    bind: { ref, onPointerMove, onPointerLeave: reset, onBlur: reset },
  };
}

/**
 * Pointer parallax normalized to [-1, 1] on each axis, sprung.
 * Multiply by a pixel amount via useTransform in the component.
 * Tracks the pointer across the whole window; static under reduced motion.
 */
export function usePointerParallax() {
  const reduce = useReducedMotion();
  const mx = useMotionValue(0);
  const my = useMotionValue(0);
  const x = useSpring(mx, { stiffness: 60, damping: 20 });
  const y = useSpring(my, { stiffness: 60, damping: 20 });

  useEffect(() => {
    if (reduce) return undefined;
    const onMove = (event) => {
      mx.set((event.clientX / window.innerWidth - 0.5) * 2);
      my.set((event.clientY / window.innerHeight - 0.5) * 2);
    };
    window.addEventListener('pointermove', onMove, { passive: true });
    return () => window.removeEventListener('pointermove', onMove);
  }, [mx, my, reduce]);

  return { x, y, reduce };
}

/**
 * Counts a number up from 0 → target once the element scrolls into view.
 * Returns a ref to attach and the current (possibly fractional) value.
 */
export function useCountUp(target, { duration = 1.5 } = {}) {
  const ref = useRef(null);
  const inView = useInView(ref, { once: true, margin: '-60px' });
  const reduce = useReducedMotion();
  const [value, setValue] = useState(0);

  useEffect(() => {
    if (!inView) return undefined;
    if (reduce) {
      setValue(target);
      return undefined;
    }
    let raf;
    const start = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - start) / (duration * 1000));
      const eased = 1 - Math.pow(1 - t, 3);
      setValue(target * eased);
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [inView, target, duration, reduce]);

  return { ref, value };
}

/**
 * Locks body scroll while `active` is true, and traps focus inside the
 * given container ref, restoring focus to the previously-focused element
 * on release. For dialogs and drawers.
 */
export function useFocusTrap(active, containerRef) {
  useEffect(() => {
    if (!active) return undefined;
    const previouslyFocused = document.activeElement;
    const { overflow } = document.body.style;
    document.body.style.overflow = 'hidden';

    const container = containerRef.current;
    const focusables = () =>
      container
        ? Array.from(
            container.querySelectorAll(
              'a[href], button:not([disabled]), textarea, input, select, [tabindex]:not([tabindex="-1"])',
            ),
          ).filter((el) => el.offsetParent !== null)
        : [];

    // Move focus into the dialog.
    const first = focusables()[0];
    first?.focus();

    const onKeyDown = (event) => {
      if (event.key !== 'Tab') return;
      const items = focusables();
      if (items.length === 0) return;
      const firstEl = items[0];
      const lastEl = items[items.length - 1];
      if (event.shiftKey && document.activeElement === firstEl) {
        event.preventDefault();
        lastEl.focus();
      } else if (!event.shiftKey && document.activeElement === lastEl) {
        event.preventDefault();
        firstEl.focus();
      }
    };

    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = overflow;
      if (previouslyFocused instanceof HTMLElement) previouslyFocused.focus();
    };
  }, [active, containerRef]);
}
