import { createContext, useContext, useMemo, useState } from 'react';
import {
  AVATAR,
  badgeCatalog,
  computeRightNow,
  contextLine,
  defaultTaste,
  experiences,
  guides,
} from '../data/mock';

const LocalIQContext = createContext(null);

const starterLogs = [
  {
    id: 'log-1',
    experienceId: 'horniman-chai',
    completedAt: '2026-09-12T08:10:00',
    summary: 'Quiet Fort morning, ₹80 chai, 2.1 km.',
  },
  {
    id: 'log-2',
    experienceId: 'sassoon-docks',
    completedAt: '2026-09-18T16:40:00',
    summary: 'Murals + harbour light. One hidden gem logged.',
  },
];

export function LocalIQProvider({ children }) {
  const [user, setUser] = useState(null);
  const [authOpen, setAuthOpen] = useState(false);
  const [language, setLanguage] = useState('en');
  const [raining, setRaining] = useState(false);
  const [hour, setHour] = useState(18);
  const [savedIds, setSavedIds] = useState(['sassoon-docks', 'bandra-bandstand']);
  const [planIds, setPlanIds] = useState(['kala-ghoda', 'horniman-chai']);
  const [logs, setLogs] = useState(starterLogs);
  const [badges, setBadges] = useState(['sunrise-specialist']);
  const [bookings, setBookings] = useState([]);
  const [meetup, setMeetup] = useState(null);
  const [groupVotes, setGroupVotes] = useState({});
  const [taste, setTaste] = useState(defaultTaste);
  const [personalization, setPersonalization] = useState(true);
  const [ignoreTaste, setIgnoreTaste] = useState(false);
  const [liveSession, setLiveSession] = useState(null);
  const [companionOpen, setCompanionOpen] = useState(false);

  const login = (data) => {
    setUser({
      name: data.name,
      email: data.email,
      phone: data.phone || '',
      photo: AVATAR,
      trustTier: data.trustTier || 1,
      isGuide: false,
    });
    setAuthOpen(false);
  };

  const logout = () => {
    setUser(null);
    setMeetup(null);
    setLiveSession(null);
  };

  const requireUser = () => {
    if (!user) {
      setAuthOpen(true);
      return false;
    }
    return true;
  };

  const toggleSave = (id) => {
    setSavedIds((current) =>
      current.includes(id) ? current.filter((item) => item !== id) : [...current, id],
    );
  };

  const addToPlan = (id) => {
    setPlanIds((current) => (current.includes(id) ? current : [...current, id]));
  };

  const removeFromPlan = (id) => {
    setPlanIds((current) => current.filter((item) => item !== id));
  };

  const completeExperience = (id, extra = {}) => {
    const experience = experiences.find((item) => item.id === id);
    const nextLogs = [
      {
        id: `log-${Date.now()}`,
        experienceId: id,
        completedAt: new Date().toISOString(),
        summary: extra.summary || `Completed ${experience?.title || 'experience'}.`,
      },
      ...logs,
    ];
    setLogs(nextLogs);

    const hiddenCount = nextLogs.filter((log) =>
      experiences.find((item) => item.id === log.experienceId)?.hiddenGem,
    ).length;
    const morningCount = nextLogs.filter((log) =>
      experiences.find((item) => item.id === log.experienceId)?.timeOfDay === 'morning',
    ).length;
    const nightFood = nextLogs.some((log) => log.experienceId === 'food-after-dark');

    setBadges((current) => {
      const next = new Set(current);
      if (hiddenCount >= 3) next.add('hidden-gem-hunter');
      if (morningCount >= 2) next.add('sunrise-specialist');
      if (nightFood) next.add('night-owl');
      if (extra.questBadge === 'Monsoon Explorer') next.add('monsoon-explorer');
      if (extra.fromGuide) next.add('guide-guest');
      return [...next];
    });
  };

  const rankedExperiences = useMemo(() => {
    return experiences
      .map((experience) => {
        const rightNow = computeRightNow(experience, { raining, hour });
        let tasteBoost = 0;
        if (personalization && !ignoreTaste) {
          experience.dna.forEach((tag) => {
            if (tag === 'morning') tasteBoost += taste.vector.morning * 8;
            if (tag === 'night') tasteBoost += taste.vector.night * 6;
            if (tag === 'photography') tasteBoost += taste.vector.photography * 6;
            if (tag === 'hidden') tasteBoost += 5;
            if (tag === 'quiet' || tag === 'chill') tasteBoost += taste.vector.chill * 4;
          });
        }
        return {
          ...experience,
          rightNow,
          context: contextLine(experience, raining),
          rank: rightNow + tasteBoost,
        };
      })
      .sort((a, b) => b.rank - a.rank);
  }, [raining, hour, personalization, ignoreTaste, taste]);

  const value = {
    user,
    login,
    logout,
    authOpen,
    setAuthOpen,
    requireUser,
    language,
    setLanguage,
    raining,
    setRaining,
    hour,
    setHour,
    savedIds,
    toggleSave,
    planIds,
    addToPlan,
    removeFromPlan,
    logs,
    completeExperience,
    badges,
    badgeCatalog,
    bookings,
    setBookings,
    meetup,
    setMeetup,
    groupVotes,
    setGroupVotes,
    taste,
    setTaste,
    personalization,
    setPersonalization,
    ignoreTaste,
    setIgnoreTaste,
    liveSession,
    setLiveSession,
    companionOpen,
    setCompanionOpen,
    rankedExperiences,
    guides,
    setUser,
  };

  return <LocalIQContext.Provider value={value}>{children}</LocalIQContext.Provider>;
}

export function useLocalIQ() {
  const context = useContext(LocalIQContext);
  if (!context) throw new Error('useLocalIQ must be used inside LocalIQProvider');
  return context;
}
