import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { guides } from '../data/mock';
import { useLocalIQ } from '../context/LocalIQContext';

export default function GuideDetailPage() {
  const { id } = useParams();
  const guide = guides.find((item) => item.id === id);
  const { requireUser, bookings, setBookings, completeExperience, setUser } = useLocalIQ();
  const [hours, setHours] = useState(3);
  const [groupSize, setGroupSize] = useState(2);
  const [status, setStatus] = useState('');

  if (!guide) return <div className="px-5 py-20">Guide not found.</div>;

  const request = () => {
    if (!requireUser()) return;
    setBookings((current) => [
      {
        id: `bk-${Date.now()}`,
        guideId: guide.id,
        hours,
        groupSize,
        total: guide.rate * hours,
        status: 'requested',
      },
      ...current,
    ]);
    setStatus('Request sent. Guide can accept or decline. Chat uses a masked number in production.');
  };

  const mine = bookings.filter((item) => item.guideId === guide.id)[0];

  return (
    <div className="max-w-4xl mx-auto px-5 py-8">
      <Link to="/guides" className="font-label-md text-on-surface-variant">← Guides</Link>
      <div className="mt-4 rounded-3xl bg-surface-container-lowest p-6 flex flex-col md:flex-row gap-6">
        <img src={guide.photo} alt="" className="w-32 h-32 rounded-3xl object-cover" />
        <div>
          <h1 className="font-[Manrope] text-[32px] font-bold">{guide.name}</h1>
          <p className="font-body-lg text-on-surface-variant">{guide.bio}</p>
          <p className="font-label-md mt-2">
            {guide.languages.join(' · ')} · {guide.sample}
          </p>
          <div className="flex flex-wrap gap-1 mt-3">
            {guide.verification.map((badge) => (
              <span key={badge} className="rounded-full bg-tertiary-fixed px-2 py-1 font-label-sm">{badge}</span>
            ))}
          </div>
        </div>
      </div>

      <div className="mt-6 rounded-3xl bg-surface-container p-6">
        <h2 className="font-headline-md">Book this guide</h2>
        <div className="flex flex-wrap gap-4 mt-4">
          <label className="font-label-md">
            Hours
            <input type="number" min="1" max="6" value={hours} onChange={(e) => setHours(Number(e.target.value))} className="ml-2 rounded-xl bg-surface-container-lowest px-3 py-2 w-20" />
          </label>
          <label className="font-label-md">
            Group size
            <input type="number" min="1" max="8" value={groupSize} onChange={(e) => setGroupSize(Number(e.target.value))} className="ml-2 rounded-xl bg-surface-container-lowest px-3 py-2 w-20" />
          </label>
        </div>
        <p className="font-headline-sm mt-4">Estimate ₹{guide.rate * hours}</p>
        <button type="button" onClick={request} className="mt-4 rounded-full bg-primary-container text-on-primary px-6 py-3 font-label-lg">
          Request booking
        </button>
        {status && <p className="mt-3 font-body-md">{status}</p>}
        {mine && (
          <div className="mt-4 flex gap-2">
            <button
              type="button"
              onClick={() =>
                setBookings((current) => current.map((item) => (item.id === mine.id ? { ...item, status: 'accepted' } : item)))
              }
              className="rounded-full bg-tertiary text-on-tertiary px-4 py-2 font-label-md"
            >
              Simulate accept
            </button>
            <button
              type="button"
              onClick={() => {
                completeExperience('horniman-chai', { fromGuide: true, summary: `Tour with ${guide.name}` });
                setUser((current) => current);
              }}
              className="rounded-full bg-surface-container-lowest px-4 py-2 font-label-md"
            >
              Complete + review
            </button>
          </div>
        )}
        <p className="font-body-sm text-on-surface-variant mt-4">
          Safety: share guide details with a trusted contact. Cancellation mock: full refund 24h before.
        </p>
      </div>
    </div>
  );
}
