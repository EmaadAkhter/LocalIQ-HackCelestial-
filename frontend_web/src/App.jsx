import { Suspense, lazy } from 'react';
import { Navigate, Route, Routes, useLocation } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import Navbar from './components/Navbar';
import Footer from './components/Footer';
import AuthModal from './components/AuthModal';
import MobileTabBar from './components/MobileTabBar';
import CompanionDrawer from './components/CompanionDrawer';

const HomePage = lazy(() => import('./pages/HomePage'));
const DiscoverPage = lazy(() => import('./pages/DiscoverPage'));
const PlanPage = lazy(() => import('./pages/PlanPage'));
const MeetPage = lazy(() => import('./pages/MeetPage'));
const ProfilePage = lazy(() => import('./pages/ProfilePage'));
const ExperiencePage = lazy(() => import('./pages/ExperiencePage'));
const GuidesPage = lazy(() => import('./pages/GuidesPage'));
const GuideDetailPage = lazy(() => import('./pages/GuideDetailPage'));
const GuideStudioPage = lazy(() => import('./pages/GuideStudioPage'));
const CompanionPage = lazy(() => import('./pages/CompanionPage'));
const PassportPage = lazy(() => import('./pages/PassportPage'));
const LivePage = lazy(() => import('./pages/LivePage'));
const LabPage = lazy(() => import('./pages/LabPage'));

const pageVariants = {
  initial: { opacity: 0, y: 10 },
  in: { opacity: 1, y: 0, transition: { duration: 0.4, ease: [0.22, 1, 0.36, 1] } },
  out: { opacity: 0, y: -8, transition: { duration: 0.2 } },
};

function Page({ children }) {
  return (
    <motion.div variants={pageVariants} initial="initial" animate="in" exit="out">
      {children}
    </motion.div>
  );
}

export default function App() {
  const location = useLocation();

  return (
    <div className="min-h-screen bg-background text-on-surface">
      <Navbar />
      <main className="pt-20 pb-24 xl:pb-0">
        <Suspense fallback={<div className="flex min-h-[50vh] items-center justify-center text-on-surface-variant">Loading…</div>}>
          <AnimatePresence mode="wait">
            <Routes location={location} key={location.pathname}>
              <Route path="/" element={<Page><HomePage /></Page>} />
              <Route path="/discover" element={<Page><DiscoverPage /></Page>} />
              <Route path="/hidden-gems" element={<Page><DiscoverPage /></Page>} />
              <Route path="/plan" element={<Page><PlanPage /></Page>} />
              <Route path="/meet" element={<Page><MeetPage /></Page>} />
              <Route path="/guides" element={<Page><GuidesPage /></Page>} />
              <Route path="/guides/:id" element={<Page><GuideDetailPage /></Page>} />
              <Route path="/guide-studio" element={<Page><GuideStudioPage /></Page>} />
              <Route path="/companion" element={<Page><CompanionPage /></Page>} />
              <Route path="/passport" element={<Page><PassportPage /></Page>} />
              <Route path="/live" element={<Page><LivePage /></Page>} />
              <Route path="/live/:id" element={<Page><LivePage /></Page>} />
              <Route path="/lab" element={<Page><LabPage /></Page>} />
              <Route path="/experience/:id" element={<Page><ExperiencePage /></Page>} />
              <Route path="/profile" element={<Page><ProfilePage /></Page>} />
              <Route path="*" element={<Navigate to="/" replace />} />
            </Routes>
          </AnimatePresence>
        </Suspense>
      </main>
      <Footer />
      <MobileTabBar />
      <AuthModal />
      <CompanionDrawer />
    </div>
  );
}
