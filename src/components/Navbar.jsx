import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';

const navLinks = [
  { label: 'Explore', path: 'explore' },
  { label: 'Plan a Trip', path: 'plan-a-trip' },
  { label: 'Hidden Gems', path: 'hidden-gems' },
  { label: 'Meet Locals', path: 'meet-locals' },
  { label: 'Guides', path: 'guides' },
  { label: 'About', path: 'about' },
];

const mobileMenuVariants = {
  hidden: { opacity: 0, height: 0, y: -8 },
  visible: {
    opacity: 1,
    height: 'auto',
    y: 0,
    transition: { duration: 0.3, ease: [0.22, 1, 0.36, 1] },
  },
  exit: {
    opacity: 0,
    height: 0,
    y: -8,
    transition: { duration: 0.2, ease: 'easeIn' },
  },
};

const mobileNavItem = {
  hidden: { opacity: 0, x: -16 },
  visible: { opacity: 1, x: 0, transition: { duration: 0.25, ease: 'easeOut' } },
};

export default function Navbar() {
  const [active, setActive] = useState('explore');
  const [mobileOpen, setMobileOpen] = useState(false);
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 8);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  return (
    <>
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
        <div className="h-20 w-full max-w-7xl mx-auto px-5 flex items-center justify-between gap-4">
          {/* Logo */}
          <div className="flex items-center gap-2 shrink-0">
            <motion.img
              src="https://lh3.googleusercontent.com/aida/AEtjO1WqKJtQnBSAjhtQRGP5i3ep85oJpiAtfmOWNgTlaMmbTzheNF86UOQX_t3ANcwUnAwroFKkKdpdftebB0krnW7-o8WCBzrlcig5oEFE0TgP4XATb-VWD7YuptaBvVtqx9QkvMPU5D2zjfjIDA3ryWFczl40r-_Va8k0qesogzb7y5feruQR_7dlAFWZpGShdNuOHAimcDCw1Ac3vdUW3Oa7hbz8vYdUmpcDJzKiBrIFwWixdQaKLeS_xpA"
              alt="LocalIQ Brand Emblem"
              className="h-8 w-auto object-contain"
              whileHover={{ scale: 1.05 }}
              transition={{ duration: 0.2 }}
            />
            <div className="flex flex-col">
              <span className="font-headline-sm text-headline-sm text-on-surface tracking-tight leading-none">LocalIQ</span>
              <span className="font-body-editorial-italic text-body-editorial-italic text-on-surface-variant leading-none hidden sm:inline">
                Discover Local. Smarter.
              </span>
            </div>
          </div>

          {/* Desktop Nav */}
          <nav className="hidden xl:flex items-center gap-1">
            {navLinks.map((link) => (
              <motion.button
                key={link.path}
                onClick={() => setActive(link.path)}
                className={`px-3 py-1.5 rounded-lg font-label-lg text-label-lg transition-colors ${
                  active === link.path
                    ? 'bg-surface-container-highest text-on-surface font-semibold'
                    : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                }`}
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.97 }}
                transition={{ duration: 0.15 }}
              >
                {link.label}
              </motion.button>
            ))}
          </nav>

          {/* Right Actions */}
          <div className="flex items-center gap-2 shrink-0">
            {/* Search bar — desktop */}
            <div className="hidden md:flex items-center bg-surface-container px-3 py-1.5 rounded-full gap-1.5">
              <span className="material-symbols-outlined text-on-surface-variant text-[18px]">search</span>
              <input
                className="bg-transparent font-body-md text-body-md text-on-surface placeholder:text-on-surface-variant focus:outline-none w-48"
                placeholder="Search neighborhood, food, craft..."
                type="text"
              />
            </div>

            <a
              href="#"
              className="hidden sm:inline-flex px-3 py-1.5 font-label-md text-label-md text-on-surface-variant hover:text-on-surface transition-colors"
            >
              Sign In
            </a>

            <motion.a
              href="#"
              className="bg-primary-container hover:bg-primary text-on-primary font-label-md text-label-md px-4 py-1.5 rounded-full shadow-[0_2px_6px_-1px_rgba(46,39,36,0.12)] transition-colors flex items-center justify-center shrink-0"
              whileHover={{ scale: 1.04, y: -1 }}
              whileTap={{ scale: 0.96 }}
              transition={{ duration: 0.2 }}
            >
              Start Exploring
            </motion.a>

            <img
              src="https://lh3.googleusercontent.com/aida/AEtjO1UvDxu9a1SN0IFEcKN9qpI3wijV8Jy9cBJ-t877vR9MHw-_3Tkxs1QOeK6rT2wc_ZOqTJRDncadJVFy2CTIldvxIoeYSimDk7WClYeWs_lt2It9tJwt5GEDnP3MNoSZ931Vlvf4TLDfNnne8rRJqzONFQt8hKE_Kw1k5vgAI9EPYJKhLi17m1Bd1xBgKToRZynaNO-zpyXS5VCITm26iEUE7ik5J-KhvTjgElAAds8aIQd5Ms1J3W5iowHu"
              alt="Profile"
              className="w-8 h-8 rounded-full object-cover shadow-[0_1px_4px_rgba(46,39,36,0.12)] ml-1"
            />

            {/* Mobile hamburger */}
            <motion.button
              className="xl:hidden w-10 h-10 flex flex-col items-center justify-center gap-1.5 text-on-surface rounded-lg"
              onClick={() => setMobileOpen((v) => !v)}
              aria-label="Toggle menu"
              whileTap={{ scale: 0.92 }}
            >
              <motion.span
                className="block w-5 h-0.5 bg-on-surface rounded-full origin-center"
                animate={mobileOpen ? { rotate: 45, y: 6 } : { rotate: 0, y: 0 }}
                transition={{ duration: 0.25 }}
              />
              <motion.span
                className="block w-5 h-0.5 bg-on-surface rounded-full"
                animate={mobileOpen ? { opacity: 0 } : { opacity: 1 }}
                transition={{ duration: 0.2 }}
              />
              <motion.span
                className="block w-5 h-0.5 bg-on-surface rounded-full origin-center"
                animate={mobileOpen ? { rotate: -45, y: -6 } : { rotate: 0, y: 0 }}
                transition={{ duration: 0.25 }}
              />
            </motion.button>
          </div>
        </div>

        {/* Mobile Menu Drawer */}
        <AnimatePresence>
          {mobileOpen && (
            <motion.nav
              className="xl:hidden border-t border-outline-variant/30 bg-surface/98 backdrop-blur-md overflow-hidden"
              variants={mobileMenuVariants}
              initial="hidden"
              animate="visible"
              exit="exit"
            >
              <motion.div
                className="flex flex-col px-5 py-4 gap-1"
                variants={{ visible: { transition: { staggerChildren: 0.06, delayChildren: 0.05 } } }}
                initial="hidden"
                animate="visible"
              >
                {navLinks.map((link) => (
                  <motion.button
                    key={link.path}
                    variants={mobileNavItem}
                    onClick={() => { setActive(link.path); setMobileOpen(false); }}
                    className={`w-full text-left px-4 py-3 rounded-xl font-label-lg text-label-lg transition-colors ${
                      active === link.path
                        ? 'bg-surface-container-highest text-on-surface font-semibold'
                        : 'text-on-surface-variant hover:text-on-surface hover:bg-surface-container-high'
                    }`}
                  >
                    {link.label}
                  </motion.button>
                ))}
                <motion.a
                  variants={mobileNavItem}
                  href="#"
                  className="mt-2 w-full py-3 rounded-xl bg-primary-container text-on-primary font-label-lg text-label-lg text-center"
                >
                  Start Exploring
                </motion.a>
              </motion.div>
            </motion.nav>
          )}
        </AnimatePresence>
      </motion.header>
    </>
  );
}
