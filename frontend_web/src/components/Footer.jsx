import { Link } from 'react-router-dom';
import { motion } from 'motion/react';
import { fadeUp, viewportOnce } from '../lib/animations';
import { LOGO } from '../data/mock';

const footerLinks = {
  Explore: [
    { label: 'Right Now feed', href: '/discover' },
    { label: 'Hidden gems', href: '/hidden-gems' },
    { label: 'Experience graph', href: '/discover' },
    { label: 'Companion', href: '/companion' },
  ],
  Plan: [
    { label: 'Plan a trip', href: '/plan' },
    { label: 'Live director', href: '/live' },
    { label: 'Passport', href: '/passport' },
    { label: 'Taste profile', href: '/profile' },
  ],
  Connect: [
    { label: 'Random meetup', href: '/meet' },
    { label: 'Group vote', href: '/plan' },
    { label: 'Find a guide', href: '/guides' },
    { label: 'Guide studio', href: '/guide-studio' },
  ],
  About: [
    { label: 'Safety & trust', href: '/meet' },
    { label: 'How it works', href: '/' },
    { label: 'Profile', href: '/profile' },
    { label: 'Privacy', href: '/profile' },
  ],
};

export default function Footer() {
  return (
    <motion.footer
      className="w-full bg-inverse-surface px-5 py-12 mb-16 xl:mb-0"
      variants={fadeUp}
      initial="hidden"
      whileInView="visible"
      viewport={viewportOnce}
    >
      <div className="max-w-7xl mx-auto flex flex-col gap-10">
        <div className="flex flex-col md:flex-row gap-10 md:gap-16">
          <div className="flex flex-col gap-4 md:max-w-xs">
            <div className="flex items-center gap-2">
              <img src={LOGO} alt="LocalIQ" className="h-7 w-auto" />
              <span className="font-headline-sm text-headline-sm text-inverse-on-surface">LocalIQ</span>
            </div>
            <p className="font-body-md text-body-md text-inverse-on-surface/60 leading-relaxed">
              An experience operating system for Mumbai: feasible right now, who to go with, and how to actually live it.
            </p>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-8 flex-1">
            {Object.entries(footerLinks).map(([category, links]) => (
              <div key={category} className="flex flex-col gap-3">
                <span className="font-label-sm text-label-sm uppercase tracking-widest text-inverse-on-surface/40">
                  {category}
                </span>
                {links.map((link) => (
                  <Link
                    key={link.label}
                    to={link.href}
                    className="font-label-md text-label-md text-inverse-on-surface/60 hover:text-inverse-on-surface"
                  >
                    {link.label}
                  </Link>
                ))}
              </div>
            ))}
          </div>
        </div>
        <div className="flex items-center justify-between gap-4 pt-6 border-t border-inverse-on-surface/10">
          <span className="font-label-md text-label-md text-inverse-on-surface/40">© 2026 LocalIQ. Pilot: South Mumbai.</span>
          <span className="font-label-md text-label-md text-inverse-on-surface/40">Discover Local. Smarter.</span>
        </div>
      </div>
    </motion.footer>
  );
}
