import { useEffect, useState } from 'react';
import { Link, NavLink, useLocation } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { LOGO } from '../data/mock';
import { spring } from '../lib/animations';
import { useLocalIQ } from '../context/LocalIQContext';

const navLinks = [
  { label: 'Home', to: '/' },
  { label: 'Right Now', to: '/discover' },
  { label: 'Plan', to: '/plan' },
  { label: 'Meet', to: '/meet' },
  { label: 'Guides', to: '/guides' },
  { label: 'Companion', to: '/companion' },
  { label: 'Passport', to: '/passport' },
];

export default function Navbar() {
  const { user, logout, setAuthOpen, setCompanionOpen } = useLocalIQ();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);
  const location = useLocation();

  useEffect(() => {
    setMobileOpen(false);
  }, [location.pathname]);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 8);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <motion.header
      className={`fixed top-0 left-0 w-full z-50 transition-shadow duration-300 ${
        scrolled
          ? 'bg-surface/95 backdrop-blur-md shadow-[0_1px_8px_rgba(46,39,36,0.08)]'
          : 'bg-surface/85 backdrop-blur-md'
      }`}
      initial={{ y: -80, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={{ duration: 0.6, ease: [0.22, 1, 0.36, 1] }}
    >
      <div className="h-20 w-full max-w-[1600px] mx-auto px-5 flex items-center justify-between gap-4">
        <Link to="/" className="flex items-center gap-2 shrink-0">
          <img src={LOGO} alt="LocalIQ" className="h-8 w-auto object-contain" />
          <div className="flex flex-col">
            <span className="font-headline-sm text-headline-sm text-on-surface tracking-tight leading-none">LocalIQ</span>
            <span className="font-body-editorial-italic text-body-editorial-italic text-on-surface-variant leading-none hidden sm:inline">
              Discover Local. Smarter.
            </span>
          </div>
        </Link>

        <nav className="hidden xl:flex items-center gap-1 bg-surface-container-low/70 p-1.5 rounded-full">
          {navLinks.map((link) => (
            <NavLink
              key={link.to}
              to={link.to}
              end={link.to === '/'}
              className={({ isActive }) =>
                `relative px-3 py-1.5 rounded-full font-label-lg text-label-lg transition-colors ${
                  isActive
                    ? 'text-on-surface font-semibold'
                    : 'text-on-surface-variant hover:text-on-surface'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  {isActive && (
                    <motion.span
                      layoutId="nav-active-pill"
                      className="absolute inset-0 rounded-full bg-surface-container-highest"
                      transition={spring}
                    />
                  )}
                  <span className="relative z-10">{link.label}</span>
                </>
              )}
            </NavLink>
          ))}
        </nav>

        <div className="flex items-center gap-2 shrink-0">
          <button
            type="button"
            onClick={() => setCompanionOpen(true)}
            className="hidden md:flex items-center bg-surface-container px-3 py-1.5 rounded-full gap-1.5 text-on-surface-variant"
          >
            <span className="material-symbols-outlined text-[18px]">search</span>
            <span className="font-body-md text-body-md">Ask LocalIQ…</span>
            <span className="font-mono text-[10px] bg-surface-container-highest px-1.5 py-0.5 rounded">⌘K</span>
          </button>

          {user ? (
            <>
              <button
                type="button"
                onClick={logout}
                className="hidden sm:inline-flex px-3 py-1.5 font-label-md text-label-md text-on-surface-variant hover:text-on-surface"
              >
                Log out
              </button>
              <Link to="/profile" className="flex items-center gap-2 rounded-full border border-outline-variant/40 bg-surface-container px-2 py-1">
                <img src={user.photo} alt="" className="w-8 h-8 rounded-full object-cover" />
                <span className="hidden sm:inline font-label-md text-label-md text-on-surface">{user.name.split(' ')[0]}</span>
              </Link>
            </>
          ) : (
            <button
              type="button"
              onClick={() => setAuthOpen(true)}
              className="hidden sm:inline-flex px-3 py-1.5 font-label-md text-label-md text-on-surface-variant hover:text-on-surface"
            >
              Sign In
            </button>
          )}

          <Link
            to="/discover"
            className="bg-primary-container hover:bg-primary text-on-primary font-label-md text-label-md px-4 py-1.5 rounded-full shadow-sm"
          >
            {user ? 'Explore now' : 'Start Exploring'}
          </Link>

          <button
            className="xl:hidden w-10 h-10 flex flex-col items-center justify-center gap-1.5 rounded-lg"
            onClick={() => setMobileOpen((v) => !v)}
            aria-label="Toggle menu"
            type="button"
          >
            <span className="block w-5 h-0.5 bg-on-surface rounded-full" />
            <span className="block w-5 h-0.5 bg-on-surface rounded-full" />
            <span className="block w-5 h-0.5 bg-on-surface rounded-full" />
          </button>
        </div>
      </div>

      <AnimatePresence>
        {mobileOpen && (
          <motion.nav
            className="xl:hidden bg-surface/98 backdrop-blur-md overflow-hidden"
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
          >
            <div className="flex flex-col px-5 py-4 gap-1 pb-6">
              {navLinks.map((link) => (
                <NavLink
                  key={link.to}
                  to={link.to}
                  className="px-4 py-3 rounded-xl font-label-lg text-label-lg text-on-surface-variant hover:bg-surface-container-high"
                >
                  {link.label}
                </NavLink>
              ))}
              <Link to="/profile" className="px-4 py-3 rounded-xl font-label-lg text-label-lg">
                Profile
              </Link>
            </div>
          </motion.nav>
        )}
      </AnimatePresence>
    </motion.header>
  );
}
