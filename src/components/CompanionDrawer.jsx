import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { AnimatePresence, motion } from 'motion/react';
import { springSoft } from '../lib/animations';
import { useFocusTrap } from '../lib/motionHooks';
import { useLocalIQ } from '../context/LocalIQContext';

const copy = {
  en: {
    title: 'LocalIQ Companion',
    hint: 'Tell me what you want — in English, Hindi, or Marathi.',
    send: 'Send',
  },
  hi: {
    title: 'LocalIQ साथी',
    hint: 'बताइए आपके पास कितना समय और बजट है।',
    send: 'भेजें',
  },
  mr: {
    title: 'LocalIQ साथी',
    hint: 'तुम्हाला काय हवं ते सांगा — वेळ, बजेट, मूड.',
    send: 'पाठवा',
  },
};

function detectLanguage(text) {
  if (/[अ-ह]/.test(text) && /आहे|हवं|तुम्ही/.test(text)) return 'mr';
  if (/[अ-ह]/.test(text)) return 'hi';
  return 'en';
}

function replyFor(text, ranked, language) {
  const lower = text.toLowerCase();
  const indoor = /indoor|बारिश|पाऊस|rain/.test(lower);
  const cheap = /cheap|800|₹|budget|सस्ता/.test(lower);
  const morning = /morning|sunrise|सुबह/.test(lower);
  let pool = ranked;
  if (indoor) pool = pool.filter((item) => item.rainSafe);
  if (cheap) pool = pool.filter((item) => item.cost <= 400);
  if (morning) pool = pool.filter((item) => item.timeOfDay === 'morning');
  const picks = (pool.length ? pool : ranked).slice(0, 3);
  const names = picks.map((item) => item.title).join(', ');
  if (language === 'hi') {
    return `समझ गई। आपके लिए अभी बेहतर विकल्प: ${names}। Indoor/बारिश के हिसाब से रैंक किया है। और सस्ता चाहिए या गाइड?`;
  }
  if (language === 'mr') {
    return `समजलं. आत्ता चांगले पर्याय: ${names}. हवा बदला किंवा बजेट सांगा, मी प्लॅन बदलते.`;
  }
  return `Noted. Right now I’d start with ${names}. ${indoor ? 'I prioritized indoor and rain-safe stops.' : 'I used live weather, crowd, and your taste profile.'} Want something cheaper, closer, or with a verified guide?`;
}

export default function CompanionDrawer() {
  const { companionOpen, setCompanionOpen, rankedExperiences, language, setLanguage, setTaste } = useLocalIQ();
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState([
    {
      role: 'bot',
      text: 'I have 2 hours and want something local. You can also say: “Mere paas 2 ghante hain, kuch indoor chahiye.”',
    },
  ]);
  const navigate = useNavigate();
  const ui = copy[language] || copy.en;
  const panelRef = useRef(null);
  useFocusTrap(companionOpen, panelRef);

  useEffect(() => {
    const onKey = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setCompanionOpen(true);
      }
      if (event.key === 'Escape') setCompanionOpen(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [setCompanionOpen]);

  const suggestions = useMemo(() => rankedExperiences.slice(0, 3), [rankedExperiences]);

  const send = (raw) => {
    const text = (raw || input).trim();
    if (!text) return;
    const lang = detectLanguage(text);
    setLanguage(lang);
    if (/nightlife|रात/.test(text.toLowerCase())) {
      setTaste((current) => ({
        ...current,
        text: `${current.text} Recently asked for more nightlife.`,
        vector: { ...current.vector, night: 0.7 },
      }));
    }
    const answer = replyFor(text, rankedExperiences, lang);
    setMessages((current) => [...current, { role: 'user', text }, { role: 'bot', text: answer, picks: suggestions }]);
    setInput('');
  };

  return (
    <AnimatePresence>
      {companionOpen && (
        <>
          <motion.div
            className="fixed inset-0 z-[85] bg-[#211a17]/40 backdrop-blur-[2px]"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setCompanionOpen(false)}
          />
          <motion.aside
            ref={panelRef}
            role="dialog"
            aria-modal="true"
            aria-label={ui.title}
            className="fixed inset-y-0 right-0 z-[90] w-full max-w-md bg-surface-container-lowest shadow-[-16px_0_40px_rgba(33,26,23,0.16)] flex flex-col"
            initial={{ x: '100%' }}
            animate={{ x: 0 }}
            exit={{ x: '100%' }}
            transition={springSoft}
          >
          <div className="h-20 px-5 flex items-center justify-between">
            <div>
              <p className="font-label-sm text-label-sm text-primary uppercase tracking-widest">{ui.title}</p>
              <p className="font-body-sm text-body-sm text-on-surface-variant">{ui.hint}</p>
            </div>
            <div className="flex gap-1">
              {['en', 'hi', 'mr'].map((code) => (
                <button
                  key={code}
                  type="button"
                  onClick={() => setLanguage(code)}
                  className={`px-2 py-1 rounded-full font-label-sm text-label-sm ${
                    language === code ? 'bg-primary-container text-on-primary' : 'bg-surface-container'
                  }`}
                >
                  {code.toUpperCase()}
                </button>
              ))}
              <button type="button" aria-label="Close companion" className="ml-1 w-9 h-9 rounded-full bg-surface-container" onClick={() => setCompanionOpen(false)}>
                <span className="material-symbols-outlined">close</span>
              </button>
            </div>
          </div>

          <div className="flex-1 overflow-y-auto px-5 pb-4 flex flex-col gap-3">
            {messages.map((message, index) => (
              <div
                key={index}
                className={`rounded-2xl px-4 py-3 max-w-[90%] ${
                  message.role === 'user'
                    ? 'self-end bg-primary-container text-on-primary'
                    : 'self-start bg-surface-container text-on-surface'
                }`}
              >
                <p className="font-body-md text-body-md">{message.text}</p>
              </div>
            ))}
            <div className="grid grid-cols-1 gap-2 mt-2">
              {suggestions.map((item) => (
                <Link
                  key={item.id}
                  to={`/experience/${item.id}`}
                  onClick={() => setCompanionOpen(false)}
                  className="rounded-xl bg-surface-container-low p-3 flex gap-3"
                >
                  <img src={item.img} alt="" className="w-14 h-14 rounded-lg object-cover" />
                  <div>
                    <p className="font-headline-sm text-headline-sm">{item.title}</p>
                    <p className="font-label-sm text-label-sm text-on-surface-variant">
                      {item.rightNow}% right now · {item.costLabel}
                    </p>
                  </div>
                </Link>
              ))}
            </div>
          </div>

          <form
            className="p-4 flex gap-2"
            onSubmit={(event) => {
              event.preventDefault();
              send();
            }}
          >
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              className="flex-1 rounded-xl bg-surface-container px-3 py-3 font-body-md"
              placeholder="2 hours, ₹800, indoor…"
            />
            <button type="submit" className="rounded-xl bg-primary-container text-on-primary px-4 font-label-md">
              {ui.send}
            </button>
          </form>
          <button
            type="button"
            className="mx-4 mb-4 font-label-md text-label-md text-primary"
            onClick={() => {
              setCompanionOpen(false);
              navigate('/companion');
            }}
          >
            Open full companion →
          </button>
        </motion.aside>
        </>
      )}
    </AnimatePresence>
  );
}
