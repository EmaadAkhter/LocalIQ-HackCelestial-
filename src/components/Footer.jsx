import { motion } from 'motion/react';
import { fadeUp, viewportOnce } from '../lib/animations';

const footerLinks = {
  Explore: ['Neighborhoods', 'Hidden Gems', 'Food & Chai', 'Heritage Walks', 'Map Discovery'],
  Plan: ['Plan a Trip', '3-Day Itinerary', 'Itinerary Studio', 'AI Suggestions', 'Save & Share'],
  Connect: ['Meet Locals', 'Random Meetup', 'Become a Guide', 'Community Board', 'Stories'],
  About: ['Our Mission', 'How It Works', 'Contributors', 'Press', 'Privacy Policy'],
};

export default function Footer() {
  return (
    <motion.footer
      className="w-full bg-inverse-surface px-5 py-12"
      variants={fadeUp}
      initial="hidden"
      whileInView="visible"
      viewport={viewportOnce}
    >
      <div className="max-w-7xl mx-auto flex flex-col gap-10">
        {/* Top row */}
        <div className="flex flex-col md:flex-row gap-10 md:gap-16">
          {/* Brand */}
          <div className="flex flex-col gap-4 md:max-w-xs">
            <div className="flex items-center gap-2">
              <img
                src="https://lh3.googleusercontent.com/aida/AEtjO1WqKJtQnBSAjhtQRGP5i3ep85oJpiAtfmOWNgTlaMmbTzheNF86UOQX_t3ANcwUnAwroFKkKdpdftebB0krnW7-o8WCBzrlcig5oEFE0TgP4XATb-VWD7YuptaBvVtqx9QkvMPU5D2zjfjIDA3ryWFczl40r-_Va8k0qesogzb7y5feruQR_7dlAFWZpGShdNuOHAimcDCw1Ac3vdUW3Oa7hbz8vYdUmpcDJzKiBrIFwWixdQaKLeS_xpA"
                alt="LocalIQ"
                className="h-7 w-auto"
              />
              <span className="font-headline-sm text-headline-sm text-inverse-on-surface">LocalIQ</span>
            </div>
            <p className="font-body-md text-body-md text-inverse-on-surface/60 leading-relaxed">
              Mumbai's most thoughtful neighborhood intelligence platform. Built with 140+ locals,
              for anyone who wants to feel the city.
            </p>
            <div className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-tertiary" />
              <span className="font-label-sm text-label-sm text-inverse-on-surface/60">
                Mumbai, India
              </span>
            </div>
          </div>

          {/* Links */}
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-8 flex-1">
            {Object.entries(footerLinks).map(([category, links]) => (
              <div key={category} className="flex flex-col gap-3">
                <span className="font-label-sm text-label-sm uppercase tracking-widest text-inverse-on-surface/40">
                  {category}
                </span>
                <div className="flex flex-col gap-2">
                  {links.map((link) => (
                    <motion.a
                      key={link}
                      href="#"
                      className="font-label-md text-label-md text-inverse-on-surface/60 hover:text-inverse-on-surface transition-colors"
                      whileHover={{ x: 3 }}
                      transition={{ duration: 0.15 }}
                    >
                      {link}
                    </motion.a>
                  ))}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Bottom row */}
        <div className="flex flex-col sm:flex-row items-center justify-between gap-4 pt-6 border-t border-inverse-on-surface/10">
          <span className="font-label-md text-label-md text-inverse-on-surface/40">
            © 2026 LocalIQ. Made with care in Mumbai.
          </span>
          <div className="flex items-center gap-1 text-inverse-on-surface/40 font-label-md text-label-md">
            <span className="material-symbols-outlined text-[14px] text-primary-fixed-dim">favorite</span>
            Discover Local. Smarter.
          </div>
        </div>
      </div>
    </motion.footer>
  );
}
