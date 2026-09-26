import { useMemo, useState } from 'react';
import { calculateMatchScore, demoUserProfile, matchQuestions, people } from '../data/mock';
import { useLocalIQ } from '../context/LocalIQContext';

export default function MeetPage() {
  const { user, requireUser, setUser, meetup, setMeetup } = useLocalIQ();
  const [emergency, setEmergency] = useState(false);
  const [shared, setShared] = useState(false);
  const [responses, setResponses] = useState(demoUserProfile.answers);
  const tier = user?.trustTier || 0;

  const matches = useMemo(
    () =>
      people
        .map((person) => ({
          ...person,
          match: calculateMatchScore(responses, person.answers),
        }))
        .filter((person) => person.match >= 60)
        .sort((a, b) => b.match - a.match),
    [responses],
  );

  const requestMeetup = (person) => {
    if (!requireUser()) return;
    if (tier < 2) return;
    setMeetup({
      person,
      place: 'Horniman Circle Gardens — public meeting point',
      when: 'Today, 6:30 PM',
      expires: 'Starts within 90 minutes or auto-expires',
      status: 'matched',
    });
  };

  const updateResponse = (questionId, value) => {
    setResponses((current) => ({
      ...current,
      [questionId]: value,
    }));
  };

  return (
    <div className="max-w-6xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">Person → person</p>
      <h1 className="font-[Manrope] text-[40px] font-bold tracking-[-0.04em]">Anonymous compatibility matching</h1>
      <p className="font-body-lg text-on-surface-variant mt-2 max-w-3xl">
        People are matched on shared hangout preferences before profile details are revealed. Only age and gender are shown until the match is accepted.
      </p>

      <div className="grid md:grid-cols-3 gap-4 mt-8">
        {[
          ['Tier 1 — Basic', 'Email + phone + photo', 'Recommendations only'],
          ['Tier 2 — ID-verified', 'Government ID + review', 'Random Meetup, stranger quests'],
          ['Tier 3 — Enhanced', 'Successful meetups + ratings', 'Host public quests'],
        ].map((row, index) => (
          <div
            key={row[0]}
            className={`rounded-2xl p-4 ${tier === index + 1 ? 'bg-primary-container text-on-primary' : 'bg-surface-container'}`}
          >
            <p className="font-headline-sm">{row[0]}</p>
            <p className="font-body-sm mt-1 opacity-80">{row[1]}</p>
            <p className="font-label-md mt-2">{row[2]}</p>
          </div>
        ))}
      </div>

      {user && tier < 2 && (
        <div className="mt-6 rounded-2xl bg-surface-container-low p-5 flex flex-col md:flex-row md:items-center justify-between gap-3">
          <p className="font-body-md">Simulate ID verification to unlock anonymous stranger connect. ID images stay in a separate KYC mock — only status is stored here.</p>
          <button
            type="button"
            onClick={() => setUser((current) => ({ ...current, trustTier: 2 }))}
            className="rounded-full bg-primary-container text-on-primary px-5 py-3 font-label-md"
          >
            Verify ID (demo)
          </button>
        </div>
      )}

      <div className="mt-8 rounded-3xl bg-surface-container p-5">
        <h2 className="font-headline-sm">Tell us how you want to hang out</h2>
        <div className="mt-5 space-y-5">
          {matchQuestions.map((question) => (
            <div key={question.id}>
              <p className="font-label-md text-on-surface-variant mb-2">{question.label}</p>
              <div className="flex flex-wrap gap-2">
                {question.options.map((option) => {
                  const active = responses[question.id] === option;

                  return (
                    <button
                      key={option}
                      type="button"
                      onClick={() => updateResponse(question.id, option)}
                      className={`rounded-full px-3 py-2 font-label-sm transition ${
                        active ? 'bg-primary-container text-on-primary' : 'bg-surface-container-lowest text-on-surface-variant'
                      }`}
                    >
                      {option}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      <div className="mt-8">
        <p className="font-label-sm uppercase tracking-widest text-primary">Best anonymous matches</p>
        <div className="grid md:grid-cols-3 gap-5 mt-4">
          {matches.length > 0 ? (
            matches.map((person) => (
              <article key={person.id} className="rounded-3xl bg-surface-container-lowest p-5 shadow-sm">
                <div className="flex items-center gap-4">
                  <img src={person.photo} alt="" className="w-16 h-16 rounded-full object-cover" />
                  <div>
                    <p className="font-label-sm uppercase tracking-widest text-primary">Anonymous match</p>
                    <h3 className="font-headline-sm mt-1">{person.age}, {person.gender}</h3>
                  </div>
                </div>

                <p className="font-label-sm text-tertiary mt-4">{person.match}% compatibility</p>
                <p className="font-body-md text-on-surface-variant mt-2">{person.why}</p>

                <div className="flex flex-wrap gap-1 mt-3">
                  {person.badges.map((badge) => (
                    <span key={badge} className="rounded-full bg-secondary-container px-2 py-1 font-label-sm">{badge}</span>
                  ))}
                </div>

                <button
                  type="button"
                  onClick={() => requestMeetup(person)}
                  className="mt-4 w-full rounded-full bg-primary-container text-on-primary py-2.5 font-label-md disabled:opacity-40"
                  disabled={tier < 2}
                >
                  {tier < 2 ? 'Locked until ID-verified' : 'Request meetup'}
                </button>
              </article>
            ))
          ) : (
            <div className="md:col-span-3 rounded-3xl bg-surface-container-lowest p-6 text-on-surface-variant">
              Your answers are too different from the current profiles. Try a broader vibe or budget to surface more anonymous matches.
            </div>
          )}
        </div>
      </div>

      {meetup && (
        <div className="mt-10 rounded-3xl bg-surface-container p-6">
          <p className="font-label-sm uppercase text-primary">Shared plan</p>
          <h2 className="font-headline-lg">With {meetup.person.name}</h2>
          <p className="font-body-md mt-2">{meetup.place}</p>
          <p className="font-body-md">{meetup.when} · {meetup.expires}</p>
          <p className="font-body-sm text-on-surface-variant mt-2">Exact home address is never shared before acceptance. First meet is public only.</p>
          <div className="flex flex-wrap gap-2 mt-4">
            <button type="button" onClick={() => setShared(true)} className="rounded-full bg-surface-container-lowest px-4 py-2 font-label-md">
              {shared ? 'Details sent to trusted contact' : 'Share with a trusted contact'}
            </button>
            <button type="button" onClick={() => setEmergency(true)} className="rounded-full bg-error text-on-error px-4 py-2 font-label-md">
              Emergency
            </button>
            <button type="button" onClick={() => setMeetup(null)} className="rounded-full bg-surface-container-highest px-4 py-2 font-label-md">
              Block / cancel
            </button>
            {user?.trustTier === 2 && (
              <button
                type="button"
                onClick={() => setUser((current) => ({ ...current, trustTier: 3 }))}
                className="rounded-full bg-tertiary text-on-tertiary px-4 py-2 font-label-md"
              >
                Complete meetup → Tier 3
              </button>
            )}
          </div>
          {emergency && (
            <p className="mt-3 font-body-md text-error">Incident mock opened. Account would be paused during review.</p>
          )}
        </div>
      )}
    </div>
  );
}
