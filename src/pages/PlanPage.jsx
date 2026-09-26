import { Link, useNavigate } from 'react-router-dom';
import { motion } from 'motion/react';
import { useLocalIQ } from '../context/LocalIQContext';
import ItinerarySection from '../components/ItinerarySection';
import { experiences, quests } from '../data/mock';

export default function PlanPage() {
  const { planIds, removeFromPlan, addToPlan, groupVotes, setGroupVotes, completeExperience, rankedExperiences, setLiveSession } =
    useLocalIQ();
  const navigate = useNavigate();
  const planned = planIds.map((id) => rankedExperiences.find((item) => item.id === id)).filter(Boolean);
  const totalHrs = planned.reduce((sum, item) => sum + item.durationHrs, 0);
  const totalCost = planned.reduce((sum, item) => sum + item.cost, 0);

  const vote = (id) => {
    setGroupVotes((current) => ({ ...current, [id]: (current[id] || 1) + 1 }));
  };

  const winner = [...planned].sort((a, b) => (groupVotes[b.id] || 1) - (groupVotes[a.id] || 1))[0];

  return (
    <div className="max-w-6xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">Group decision + itinerary</p>
      <h1 className="font-[Manrope] text-[40px] font-bold tracking-[-0.04em]">Plan your Mumbai time</h1>
      <p className="font-[Newsreader] italic text-on-surface-variant mt-1">
        Dynamic path picking: keep the 3 stops that fit time, budget, and energy.
      </p>

      <div className="mt-8 rounded-3xl border border-outline-variant bg-surface-container-lowest p-4">
        <p className="font-label-sm uppercase tracking-widest text-primary">Tourist mode</p>
        <p className="font-body-md text-on-surface-variant mt-1">
          Start with a ready-made 3-day route or build from your own saved experiences.
        </p>
      </div>

      <div className="mt-8">
        <ItinerarySection id="tourist-itinerary" />
      </div>

      <div className="grid lg:grid-cols-3 gap-6 mt-8">
        <div className="lg:col-span-2 space-y-4">
          {planned.length === 0 && (
            <div className="rounded-3xl bg-surface-container p-8 text-center">
              <p>Your plan is empty.</p>
              <Link to="/discover" className="text-primary font-label-lg">Add from Right Now</Link>
            </div>
          )}
          {planned.map((item, index) => (
            <motion.div
              key={item.id}
              layout
              className="rounded-2xl bg-surface-container-lowest p-4 flex gap-4 items-center"
            >
              <span className="font-headline-sm text-primary-container">0{index + 1}</span>
              <img src={item.img} alt="" className="w-20 h-20 rounded-lg object-cover" />
              <div className="flex-1">
                <Link to={`/experience/${item.id}`} className="font-headline-sm">{item.title}</Link>
                <p className="font-label-sm text-on-surface-variant">
                  {item.durationHrs}h · {item.costLabel} · votes {groupVotes[item.id] || 1}
                </p>
              </div>
              <button type="button" onClick={() => vote(item.id)} className="rounded-full bg-surface-container px-3 py-2 font-label-sm">
                Vote
              </button>
              <button type="button" onClick={() => removeFromPlan(item.id)} className="w-10 h-10 rounded-full bg-surface-container">
                <span className="material-symbols-outlined">close</span>
              </button>
            </motion.div>
          ))}
        </div>

        <aside className="space-y-4">
          <div className="rounded-3xl bg-inverse-surface text-inverse-on-surface p-5">
            <p className="font-label-sm uppercase tracking-widest text-primary-fixed">Locked plan</p>
            <p className="font-headline-md mt-2">{totalHrs.toFixed(1)} hours · ₹{totalCost}</p>
            {winner && <p className="font-body-md mt-2">Group lean: {winner.title}</p>}
            <button
              type="button"
              disabled={!planned[0]}
              onClick={() => {
                if (!planned[0]) return;
                setLiveSession({ experienceId: planned[0].id, step: 0, optedIn: true, startedAt: Date.now() });
                navigate(`/live/${planned[0].id}`);
              }}
              className="mt-4 w-full rounded-full bg-primary-container text-on-primary py-3 font-label-lg"
            >
              Start live outing
            </button>
          </div>

          <div className="rounded-3xl bg-surface-container-low p-5">
            <p className="font-headline-sm">Hidden gem quests</p>
            {quests.map((quest) => (
              <div key={quest.id} className="mt-3">
                <p className="font-label-lg">{quest.title}</p>
                <p className="font-label-sm text-on-surface-variant">{quest.stops} stops · {quest.xp} XP · {quest.badge}</p>
                <button
                  type="button"
                  onClick={() => {
                    quest.experienceIds.forEach(addToPlan);
                    if (quest.badge === 'Monsoon Explorer') {
                      completeExperience(quest.experienceIds[0], { questBadge: 'Monsoon Explorer' });
                    }
                  }}
                  className="mt-1 font-label-md text-primary"
                >
                  Add quest to plan
                </button>
              </div>
            ))}
          </div>

          <div className="rounded-3xl bg-surface-container-lowest p-5">
            <p className="font-headline-sm mb-2">Suggested extras</p>
            {experiences
              .filter((item) => !planIds.includes(item.id))
              .slice(0, 3)
              .map((item) => (
                <button key={item.id} type="button" onClick={() => addToPlan(item.id)} className="block text-left font-label-md py-1">
                  + {item.title}
                </button>
              ))}
          </div>
        </aside>
      </div>
    </div>
  );
}
