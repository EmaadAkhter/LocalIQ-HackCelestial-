import { NavLink } from 'react-router-dom';
import { motion } from 'motion/react';
import { spring } from '../lib/animations';

const tabs = [
  { to: '/', icon: 'home', label: 'Home', end: true },
  { to: '/discover', icon: 'explore', label: 'Explore' },
  { to: '/plan', icon: 'auto_awesome', label: 'Plan' },
  { to: '/meet', icon: 'groups', label: 'Meet' },
  { to: '/profile', icon: 'person', label: 'Profile' },
];

export default function MobileTabBar() {
  return (
    <nav className="xl:hidden fixed bottom-0 inset-x-0 z-50 h-20 pb-safe bg-surface/95 backdrop-blur-xl shadow-[0_-2px_12px_rgba(46,39,36,0.06)]">
      <div className="grid grid-cols-5 h-full">
        {tabs.map((tab) => (
          <NavLink
            key={tab.to}
            to={tab.to}
            end={tab.end}
            className={({ isActive }) =>
              `relative flex flex-col items-center justify-center gap-0.5 ${
                isActive ? 'text-primary' : 'text-on-surface-variant'
              }`
            }
          >
            {({ isActive }) => (
              <>
                {isActive && (
                  <motion.span
                    layoutId="tab-active-dot"
                    className="absolute top-2 h-1 w-8 rounded-full bg-primary"
                    transition={spring}
                  />
                )}
                <motion.span
                  className="material-symbols-outlined"
                  animate={{ scale: isActive ? 1.08 : 1 }}
                  whileTap={{ scale: 0.85 }}
                  transition={spring}
                  style={{ fontVariationSettings: isActive ? "'FILL' 1" : "'FILL' 0" }}
                >
                  {tab.icon}
                </motion.span>
                <span className={`font-label-sm text-label-sm ${isActive ? 'font-bold' : ''}`}>
                  {tab.label}
                </span>
              </>
            )}
          </NavLink>
        ))}
      </div>
    </nav>
  );
}
