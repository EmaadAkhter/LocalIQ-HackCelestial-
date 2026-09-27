import { Link, useNavigate, useParams } from 'react-router-dom';
import { motion } from 'motion/react';
import { useLocalIQ } from '../context/LocalIQContext';
import { guides } from '../data/mock';
import { fadeUp } from '../lib/animations';

export default function ExperiencePage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { rankedExperiences, addToPlan, toggleSave, savedIds, planIds, completeExperience, requireUser, setLiveSession } =
    useLocalIQ();
  const experience = rankedExperiences.find((item) => item.id === id);

  if (!experience) {
    return (
      <div className="max-w-3xl mx-auto px-5 py-20 text-center">
        <h1 className="font-headline-lg">Experience not found</h1>
        <Link to="/discover" className="text-primary mt-4 inline-block">Back to Right Now</Link>
      </div>
    );
  }

  const relatedGuides = guides.filter((guide) =>
    guide.specialties.includes(experience.category) || guide.areas.includes(experience.area),
  );

  return (
    <div className="max-w-6xl mx-auto px-5 py-8">
      <button type="button" onClick={() => navigate(-1)} className="font-label-md text-on-surface-variant mb-4">
        ← Back
      </button>
      <div className="grid lg:grid-cols-12 gap-8">
        <motion.div className="lg:col-span-7" variants={fadeUp} initial="hidden" animate="visible">
          <div className="rounded-3xl overflow-hidden relative">
            <img src={experience.img} alt={experience.title} className="w-full h-[360px] object-cover" />
            <div className="absolute inset-0 bg-gradient-to-t from-on-surface/80 via-transparent to-transparent" />
            <div className="absolute bottom-5 left-5 text-white">
              <p className="font-label-sm uppercase tracking-widest text-primary-fixed">{experience.neighborhood}</p>
              <h1 className="font-[Manrope] text-[36px] font-bold leading-tight">{experience.title}</h1>
            </div>
          </div>
          <p className="font-body-lg text-body-lg text-on-surface-variant mt-5">{experience.description}</p>
          <p className="font-body-editorial-italic text-title-editorial mt-3">{experience.why}</p>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 mt-6">
            {[
              ['Right Now', `${experience.rightNow}/100`],
              ['Authenticity', `${experience.authenticity}/100`],
              ['Quality', `${experience.quality}/100`],
              ['Crowd', experience.crowd],
            ].map(([label, value]) => (
              <div key={label} className="rounded-2xl bg-surface-container p-4">
                <p className="font-label-sm text-on-surface-variant">{label}</p>
                <p className="font-headline-sm">{value}</p>
              </div>
            ))}
          </div>

          <h2 className="font-headline-md mt-8 mb-3">Route (3 stops)</h2>
          <ol className="space-y-3">
            {experience.stops.map((stop, index) => (
              <li key={stop.name} className="rounded-2xl bg-surface-container-lowest p-4 flex gap-3">
                <span className="font-headline-sm text-primary-container">0{index + 1}</span>
                <div>
                  <p className="font-headline-sm">{stop.name}</p>
                  <p className="font-body-md text-on-surface-variant">{stop.tip}</p>
                </div>
              </li>
            ))}
          </ol>
        </motion.div>

        <aside className="lg:col-span-5 flex flex-col gap-4">
          <div className="rounded-3xl bg-surface-container-lowest p-5 shadow-sm sticky top-24">
            <p className="font-label-sm text-primary uppercase tracking-widest">Feasibility</p>
            <p className="font-body-md mt-2">{experience.context}</p>
            <p className="font-label-md mt-3">{experience.bestTime} · {experience.durationHrs}h · {experience.costLabel}</p>
            {experience.deal && (
              <p className="mt-2 rounded-xl bg-tertiary-fixed px-3 py-2 font-label-md text-on-tertiary-fixed">
                {experience.deal.label} (29% off)
              </p>
            )}
            <div className="flex flex-col gap-2 mt-5">
              <button
                type="button"
                onClick={() => addToPlan(experience.id)}
                className="rounded-full bg-primary-container text-on-primary py-3 font-label-lg"
              >
                {planIds.includes(experience.id) ? 'Added to plan' : 'Add to plan'}
              </button>
              <button type="button" onClick={() => toggleSave(experience.id)} className="rounded-full bg-surface-container py-3 font-label-lg">
                {savedIds.includes(experience.id) ? 'Saved' : 'Save'}
              </button>
              <button
                type="button"
                onClick={() => {
                  setLiveSession({ experienceId: experience.id, step: 0, optedIn: true, startedAt: Date.now() });
                  navigate(`/live/${experience.id}`);
                }}
                className="rounded-full bg-inverse-surface text-inverse-on-surface py-3 font-label-lg"
              >
                Start with AI Director
              </button>
              <button
                type="button"
                onClick={() => {
                  if (!requireUser()) return;
                  completeExperience(experience.id);
                }}
                className="rounded-full border border-outline-variant/50 py-3 font-label-lg"
              >
                Mark done → Passport
              </button>
            </div>
            <div className="flex flex-wrap gap-2 mt-4">
              {experience.wheelchair && <span className="rounded-full bg-tertiary-fixed px-3 py-1 font-label-sm">Wheelchair</span>}
              {experience.lowSensory && <span className="rounded-full bg-secondary-container px-3 py-1 font-label-sm">Low sensory</span>}
              {experience.rainSafe && <span className="rounded-full bg-surface-container px-3 py-1 font-label-sm">Rain-safe</span>}
            </div>
          </div>

          <div className="rounded-3xl bg-surface-container-low p-5">
            <p className="font-headline-sm mb-3">Find a guide for this</p>
            {relatedGuides.slice(0, 2).map((guide) => (
              <Link key={guide.id} to={`/guides/${guide.id}`} className="flex items-center gap-3 py-2">
                <img src={guide.photo} alt="" className="w-12 h-12 rounded-full object-cover" />
                <div>
                  <p className="font-label-lg">{guide.name}</p>
                  <p className="font-label-sm text-on-surface-variant">₹{guide.rate}/hr · {guide.rating}★</p>
                </div>
              </Link>
            ))}
            <Link to="/guides" className="font-label-md text-primary mt-2 inline-block">See all guides</Link>
          </div>
        </aside>
      </div>
    </div>
  );
}
