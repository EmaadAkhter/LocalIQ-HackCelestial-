import { useEffect, useRef, useState } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import { spring } from '../lib/animations';
import { useFocusTrap } from '../lib/motionHooks';
import { useLocalIQ } from '../context/LocalIQContext';

export default function AuthModal() {
  const { authOpen, setAuthOpen, login } = useLocalIQ();
  const [mode, setMode] = useState('signin');
  const [form, setForm] = useState({ name: '', email: '', password: '', phone: '' });
  const panelRef = useRef(null);
  useFocusTrap(authOpen, panelRef);

  useEffect(() => {
    if (!authOpen) return;
    const onKey = (event) => {
      if (event.key === 'Escape') setAuthOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [authOpen, setAuthOpen]);

  const handleSubmit = (event) => {
    event.preventDefault();
    const email = form.email.trim();
    if (!email) return;
    const name = mode === 'signup' ? form.name.trim() || 'Traveler' : email.split('@')[0];
    login({
      name,
      email,
      phone: form.phone,
      trustTier: 1,
    });
    setForm({ name: '', email: '', password: '', phone: '' });
  };

  return (
    <AnimatePresence>
      {authOpen && (
        <motion.div
          className="fixed inset-0 z-[100] flex items-center justify-center bg-[#211a17]/55 backdrop-blur-[2px] px-4"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          onClick={() => setAuthOpen(false)}
        >
          <motion.div
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-label={mode === 'signin' ? 'Sign in to LocalIQ' : 'Create your LocalIQ account'}
            className="w-full max-w-md rounded-3xl bg-surface-container-lowest p-5 shadow-[0_24px_60px_rgba(33,26,23,0.24)]"
            initial={{ opacity: 0, scale: 0.94, y: 12 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.96, y: 8 }}
            transition={spring}
            onClick={(event) => event.stopPropagation()}
          >
        <div className="flex items-center justify-between gap-3 mb-5">
          <div>
            <p className="font-label-sm text-label-sm uppercase tracking-[0.12em] text-primary">LocalIQ</p>
            <h3 className="font-headline-md text-headline-md text-on-surface">
              {mode === 'signin' ? 'Welcome back' : 'Create your account'}
            </h3>
            <p className="font-body-sm text-body-sm text-on-surface-variant mt-1">
              Email + phone unlocks basic discovery. ID verification is only required for stranger meetups.
            </p>
          </div>
          <button
            type="button"
            onClick={() => setAuthOpen(false)}
            className="h-9 w-9 rounded-full bg-surface-container text-on-surface-variant"
            aria-label="Close"
          >
            <span className="material-symbols-outlined text-[18px]">close</span>
          </button>
        </div>

        <div className="flex rounded-full bg-surface-container p-1 mb-5">
          {['signin', 'signup'].map((item) => (
            <button
              key={item}
              type="button"
              onClick={() => setMode(item)}
              className={`flex-1 rounded-full py-2 font-label-md text-label-md ${
                mode === item ? 'bg-primary-container text-on-primary' : 'text-on-surface-variant'
              }`}
            >
              {item === 'signin' ? 'Sign in' : 'Sign up'}
            </button>
          ))}
        </div>

        <form className="flex flex-col gap-4" onSubmit={handleSubmit}>
          {mode === 'signup' && (
            <label className="flex flex-col gap-1.5">
              <span className="font-label-md text-label-md text-on-surface-variant">Name</span>
              <input
                name="name"
                value={form.name}
                onChange={(e) => setForm((c) => ({ ...c, name: e.target.value }))}
                className="w-full rounded-xl bg-surface-container px-3 py-2.5 text-body-md"
                placeholder="Your name"
              />
            </label>
          )}
          <label className="flex flex-col gap-1.5">
            <span className="font-label-md text-label-md text-on-surface-variant">Email</span>
            <input
              type="email"
              required
              value={form.email}
              onChange={(e) => setForm((c) => ({ ...c, email: e.target.value }))}
              className="w-full rounded-xl bg-surface-container px-3 py-2.5 text-body-md"
              placeholder="you@example.com"
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="font-label-md text-label-md text-on-surface-variant">Phone (Tier 1)</span>
            <input
              value={form.phone}
              onChange={(e) => setForm((c) => ({ ...c, phone: e.target.value }))}
              className="w-full rounded-xl bg-surface-container px-3 py-2.5 text-body-md"
              placeholder="+91"
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="font-label-md text-label-md text-on-surface-variant">Password</span>
            <input
              type="password"
              required
              value={form.password}
              onChange={(e) => setForm((c) => ({ ...c, password: e.target.value }))}
              className="w-full rounded-xl bg-surface-container px-3 py-2.5 text-body-md"
            />
          </label>
          <button type="submit" className="mt-2 w-full rounded-full bg-primary-container py-3 font-label-lg text-label-lg text-on-primary">
            {mode === 'signin' ? 'Sign in' : 'Create account'}
          </button>
        </form>
        </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
