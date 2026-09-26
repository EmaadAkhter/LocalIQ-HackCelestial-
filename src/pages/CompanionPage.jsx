import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useLocalIQ } from '../context/LocalIQContext';

export default function CompanionPage() {
  const { rankedExperiences, language, setLanguage, setTaste, setCompanionOpen } = useLocalIQ();
  const [log, setLog] = useState([
    { from: 'bot', text: 'What should you do? I can extract time, budget, and mood from English, Hindi, or Marathi.' },
  ]);
  const [text, setText] = useState('');

  const send = () => {
    if (!text.trim()) return;
    const rainingAsk = /rain|indoor|बारिश/.test(text.toLowerCase());
    const picks = rankedExperiences.filter((item) => (rainingAsk ? item.rainSafe : true)).slice(0, 3);
    setLog((current) => [
      ...current,
      { from: 'you', text },
      {
        from: 'bot',
        text:
          language === 'hi'
            ? `ये तीन अभी सही लग रहे हैं: ${picks.map((p) => p.title).join(', ')}.`
            : `Extracted constraints and ranked live. Try ${picks.map((p) => p.title).join(', ')}.`,
        picks,
      },
    ]);
    if (/nightlife/.test(text.toLowerCase())) {
      setTaste((current) => ({ ...current, vector: { ...current.vector, night: 0.75 } }));
    }
    setText('');
  };

  return (
    <div className="max-w-3xl mx-auto px-5 py-8">
      <p className="font-label-sm uppercase tracking-widest text-primary">Multilingual companion</p>
      <h1 className="font-[Manrope] text-[40px] font-bold">Ask in your language</h1>
      <div className="flex gap-2 mt-4">
        {['en', 'hi', 'mr'].map((code) => (
          <button
            key={code}
            type="button"
            onClick={() => setLanguage(code)}
            className={`rounded-full px-3 py-1 font-label-md ${language === code ? 'bg-primary-container text-on-primary' : 'bg-surface-container'}`}
          >
            {code === 'en' ? 'English' : code === 'hi' ? 'हिन्दी' : 'मराठी'}
          </button>
        ))}
        <button type="button" onClick={() => setCompanionOpen(true)} className="ml-auto font-label-md text-primary">
          Quick drawer
        </button>
      </div>

      <div className="mt-6 rounded-3xl bg-surface-container-lowest p-5 min-h-[420px] flex flex-col gap-3">
        {log.map((item, index) => (
          <div key={index} className={item.from === 'you' ? 'self-end bg-primary-container text-on-primary rounded-2xl px-4 py-3 max-w-[80%]' : 'self-start bg-surface-container rounded-2xl px-4 py-3 max-w-[90%]'}>
            <p className="font-body-md">{item.text}</p>
            {item.picks && (
              <div className="mt-3 space-y-2">
                {item.picks.map((pick) => (
                  <Link key={pick.id} to={`/experience/${pick.id}`} className="block font-label-md underline">
                    {pick.title} · {pick.rightNow}% now
                  </Link>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>

      <form
        className="mt-4 flex gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
      >
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          className="flex-1 rounded-2xl bg-surface-container px-4 py-3"
          placeholder="Mere paas 2 ghante hain, ₹800 budget hai…"
        />
        <button type="submit" className="rounded-2xl bg-primary-container text-on-primary px-5 font-label-lg">Send</button>
      </form>
    </div>
  );
}
