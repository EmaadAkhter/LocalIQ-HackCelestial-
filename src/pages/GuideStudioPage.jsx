import { useState } from 'react';
import { useLocalIQ } from '../context/LocalIQContext';

export default function GuideStudioPage() {
  const { requireUser, user } = useLocalIQ();
  const [tab, setTab] = useState('calendar');
  const [rate, setRate] = useState(900);
  const [pack, setPack] = useState('South Mumbai Food & Heritage — 3h');
  const [requests] = useState([
    { name: 'Aisha', when: 'Sun 10:00', status: 'new' },
    { name: 'Rohit', when: 'Mon 16:00', status: 'new' },
  ]);

  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-5 py-20 text-center">
        <h1 className="font-headline-lg">Guide studio</h1>
        <p className="text-on-surface-variant mt-2">Sign in on the traveler side first, then open studio. Guide UI stays separate by design.</p>
        <button type="button" onClick={() => requireUser()} className="mt-4 rounded-full bg-primary-container text-on-primary px-5 py-3">
          Sign in
        </button>
      </div>
    );
  }

  return (
    <div className="max-w-5xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">Guide side</p>
      <h1 className="font-[Manrope] text-[36px] font-bold">Your studio</h1>
      <p className="text-on-surface-variant">Availability, packaged experiences, requests, and payouts — not mixed with traveler copy.</p>

      <div className="flex gap-2 mt-6">
        {['calendar', 'experiences', 'requests', 'payouts', 'training'].map((item) => (
          <button
            key={item}
            type="button"
            onClick={() => setTab(item)}
            className={`rounded-full px-4 py-2 font-label-md capitalize ${tab === item ? 'bg-primary text-on-primary' : 'bg-surface-container'}`}
          >
            {item}
          </button>
        ))}
      </div>

      <div className="mt-6 rounded-3xl bg-surface-container-lowest p-6">
        {tab === 'calendar' && (
          <div>
            <p className="font-headline-sm">This week</p>
            <div className="grid grid-cols-7 gap-2 mt-4">
              {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((day, index) => (
                <div key={day + index} className="rounded-xl bg-surface-container h-24 p-2 font-label-sm">
                  {day}
                  <p className="text-tertiary mt-6">{index % 2 ? 'Open' : '2 slots'}</p>
                </div>
              ))}
            </div>
          </div>
        )}
        {tab === 'experiences' && (
          <div className="space-y-3">
            <label className="block font-label-md">
              Packaged experience
              <input value={pack} onChange={(e) => setPack(e.target.value)} className="mt-1 w-full rounded-xl bg-surface-container px-3 py-2" />
            </label>
            <label className="block font-label-md">
              Rate / hour
              <input type="number" value={rate} onChange={(e) => setRate(Number(e.target.value))} className="mt-1 w-32 rounded-xl bg-surface-container px-3 py-2" />
            </label>
            <p className="font-body-sm text-on-surface-variant">Suggested rate from demand: ₹950 this weekend.</p>
          </div>
        )}
        {tab === 'requests' && (
          <ul className="space-y-3">
            {requests.map((item) => (
              <li key={item.name} className="flex items-center justify-between rounded-2xl bg-surface-container p-4">
                <span>{item.name} · {item.when}</span>
                <span className="flex gap-2">
                  <button type="button" className="rounded-full bg-tertiary text-on-tertiary px-3 py-1 font-label-sm">Accept</button>
                  <button type="button" className="rounded-full bg-surface-container-highest px-3 py-1 font-label-sm">Decline</button>
                </span>
              </li>
            ))}
          </ul>
        )}
        {tab === 'payouts' && (
          <div>
            <p className="font-headline-md">This month ₹24,800</p>
            <p className="font-body-md text-on-surface-variant mt-2">UPI / bank payout mock. 4.9★ · 12 completed tours.</p>
          </div>
        )}
        {tab === 'training' && (
          <div>
            <p className="font-headline-sm">Micro-courses</p>
            <ul className="mt-3 space-y-2 font-body-md">
              <li>Safety & public meeting points — certified</li>
              <li>Inclusivity & accessibility notes — in progress</li>
              <li>Storytelling vs information-heavy DNA — locked</li>
            </ul>
          </div>
        )}
      </div>
    </div>
  );
}
