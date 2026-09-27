import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { useLocalIQ } from '../context/LocalIQContext';

export default function LivePage() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { rankedExperiences, liveSession, setLiveSession, completeExperience, raining, setRaining, requireUser } = useLocalIQ();
  const experience = rankedExperiences.find((item) => item.id === (id || liveSession?.experienceId)) || rankedExperiences[0];
  const [step, setStep] = useState(liveSession?.step || 0);
  const [optedIn, setOptedIn] = useState(liveSession?.optedIn !== false);
  const [done, setDone] = useState(false);

  const tips = experience.stops.map((stop, index) => ({
    ...stop,
    extra:
      index === 1
        ? 'Photography: the cleanest angle is from the left, 10 minutes before peak light.'
        : 'Safety: stay on the lit public stretch; skip shortcuts after dusk.',
  }));

  const summary = useMemo(
    () => ({
      km: (experience.distanceKm + step * 0.7).toFixed(1),
      spend: experience.cost + step * 40,
      stops: step + 1,
      insight: experience.hiddenGem ? 'You found a hidden gem most visitors skip.' : 'You stayed on a high-feasibility path.',
    }),
    [experience, step],
  );

  if (done) {
    return (
      <div className="max-w-2xl mx-auto px-5 py-16 text-center">
        <p className="font-label-sm uppercase text-primary">Post-experience</p>
        <h1 className="font-[Manrope] text-[36px] font-bold">You walked {summary.km} km</h1>
        <p className="font-body-lg mt-3">Spent about ₹{summary.spend} · {summary.stops} stops · {summary.insight}</p>
        <div className="flex justify-center gap-3 mt-6">
          <button
            type="button"
            onClick={() => {
              if (!requireUser()) return;
              completeExperience(experience.id, { summary: `Live outing: ${summary.km} km, ₹${summary.spend}` });
              navigate('/passport');
            }}
            className="rounded-full bg-primary-container text-on-primary px-5 py-3 font-label-lg"
          >
            Save to passport
          </button>
          <Link to="/discover" className="rounded-full bg-surface-container px-5 py-3 font-label-lg">
            Find the next hour
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="max-w-3xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">AI Experience Director</p>
      <h1 className="font-[Manrope] text-[36px] font-bold">{experience.title}</h1>
      <p className="text-on-surface-variant">Live companion for before, during, and after — not only planning.</p>

      <div className="flex gap-2 mt-4">
        <button type="button" onClick={() => setOptedIn((v) => !v)} className="rounded-full bg-surface-container px-4 py-2 font-label-md">
          {optedIn ? 'Live tips on' : 'Live tips paused'}
        </button>
        <button type="button" onClick={() => setRaining((v) => !v)} className="rounded-full bg-surface-container px-4 py-2 font-label-md">
          {raining ? 'Rain adaptation on' : 'Trigger rain'}
        </button>
      </div>

      {raining && (
        <div className="mt-4 rounded-2xl bg-surface-container p-4">
          Rain starting in 15 minutes. Concrete adaptation: duck into the Kala Ghoda indoor atelier hop, 6 minutes away.
          <Link to="/experience/kala-ghoda" className="block text-primary mt-2 font-label-md">Open indoor alternative</Link>
        </div>
      )}

      <ol className="mt-6 space-y-4">
        {tips.map((stop, index) => (
          <li
            key={stop.name}
            className={`rounded-3xl p-5 ${index === step ? 'bg-surface-container-lowest shadow-md' : 'bg-surface-container'}`}
          >
            <p className="font-headline-sm">0{index + 1} {stop.name}</p>
            {optedIn ? (
              <>
                <p className="font-body-md mt-2">{stop.tip}</p>
                <p className="font-body-editorial-italic mt-1">{stop.extra}</p>
              </>
            ) : (
              <p className="font-body-md mt-2 text-on-surface-variant">Guidance paused. The outing still continues.</p>
            )}
          </li>
        ))}
      </ol>

      <div className="flex gap-3 mt-6">
        {step < tips.length - 1 ? (
          <button
            type="button"
            onClick={() => {
              const next = step + 1;
              setStep(next);
              setLiveSession({ experienceId: experience.id, step: next, optedIn, startedAt: Date.now() });
            }}
            className="rounded-full bg-primary-container text-on-primary px-6 py-3 font-label-lg"
          >
            Arrive at next stop
          </button>
        ) : (
          <button type="button" onClick={() => setDone(true)} className="rounded-full bg-primary-container text-on-primary px-6 py-3 font-label-lg">
            End outing
          </button>
        )}
      </div>
    </div>
  );
}
