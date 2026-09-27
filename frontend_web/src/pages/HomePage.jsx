import { Link } from 'react-router-dom';
import { useLocalIQ } from '../context/LocalIQContext';
import HeroSection from '../components/HeroSection';
import DiscoverySection from '../components/DiscoverySection';
import ExploreFeedSection from '../components/ExploreFeedSection';
import HowItWorksSection from '../components/HowItWorksSection';
import CTASection from '../components/CTASection';

export default function HomePage() {
  const { user, setAuthOpen } = useLocalIQ();

  return (
    <>
      <HeroSection id="top" user={user} onOpenAuth={() => setAuthOpen(true)} />

      <section className="w-full px-5 pb-8">
        <div className="max-w-6xl mx-auto">
          <div className="mb-5 flex items-center justify-between gap-3">
            <h2 className="font-[Manrope] text-[26px] md:text-[32px] font-bold tracking-[-0.03em] text-on-surface">
              Choose your starting point
            </h2>
            <span className="hidden sm:inline font-label-sm uppercase tracking-widest text-on-surface-variant">
              Simple first steps
            </span>
          </div>

          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <Link
              to="/discover"
              className="rounded-3xl border border-outline-variant bg-surface-container-lowest p-5 hover:bg-surface-container transition-colors"
            >
              <p className="font-label-sm uppercase tracking-widest text-primary">01</p>
              <h3 className="font-headline-sm mt-2">Explore</h3>
              <p className="font-body-md text-on-surface-variant mt-2">
                Browse neighborhoods, hidden gems, and what feels good right now.
              </p>
            </Link>

            <Link
              to="/plan"
              className="rounded-3xl border border-outline-variant bg-surface-container-lowest p-5 hover:bg-surface-container transition-colors"
            >
              <p className="font-label-sm uppercase tracking-widest text-primary">02</p>
              <h3 className="font-headline-sm mt-2">Plan a trip</h3>
              <p className="font-body-md text-on-surface-variant mt-2">
                Open the 3-day tourist planner only when you want a full guided route.
              </p>
            </Link>

            <Link
              to="/meet"
              className="rounded-3xl border border-outline-variant bg-surface-container-lowest p-5 hover:bg-surface-container transition-colors"
            >
              <p className="font-label-sm uppercase tracking-widest text-primary">03</p>
              <h3 className="font-headline-sm mt-2">Meet locally</h3>
              <p className="font-body-md text-on-surface-variant mt-2">
                Go to the dedicated matching page when you want to connect with people.
              </p>
            </Link>
          </div>
        </div>
      </section>

      <DiscoverySection id="explore" />
      <ExploreFeedSection id="hidden-gems" />
      <HowItWorksSection id="guides" />
      <CTASection id="about" onOpenAuth={() => setAuthOpen(true)} />
    </>
  );
}
