import { motion } from 'motion/react';
import Navbar from './components/Navbar';
import HeroSection from './components/HeroSection';
import DiscoverySection from './components/DiscoverySection';
import ExploreFeedSection from './components/ExploreFeedSection';
import HowItWorksSection from './components/HowItWorksSection';
import ItinerarySection from './components/ItinerarySection';
import MeetLocalsSection from './components/MeetLocalsSection';
import CTASection from './components/CTASection';
import Footer from './components/Footer';
import './App.css';

// Page transition wrapper
const pageVariants = {
  initial: { opacity: 0, y: 8 },
  in: { opacity: 1, y: 0, transition: { duration: 0.45, ease: [0.22, 1, 0.36, 1] } },
  out: { opacity: 0, y: -8, transition: { duration: 0.25, ease: 'easeIn' } },
};

function App() {
  return (
    <div className="min-h-screen bg-background text-on-surface">
      <Navbar />
      <motion.main
        className="pt-20"
        variants={pageVariants}
        initial="initial"
        animate="in"
        exit="out"
      >
        <HeroSection />
        <DiscoverySection />
        <ExploreFeedSection />
        <HowItWorksSection />
        <ItinerarySection />
        <MeetLocalsSection />
        <CTASection />
      </motion.main>
      <Footer />
    </div>
  );
}

export default App;
