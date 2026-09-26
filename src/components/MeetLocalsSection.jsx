import { motion } from 'motion/react';
import { fadeUp, scaleIn, staggerContainer, viewportOnce } from '../lib/animations';

const meetupProfiles = [
  {
    id: 'p1',
    name: 'Priya S.',
    role: 'Local Guide · Fort & Colaba',
    avatar: 'https://lh3.googleusercontent.com/aida/AEtjO1UvDxu9a1SN0IFEcKN9qpI3wijV8Jy9cBJ-t877vR9MHw-_3Tkxs1QOeK6rT2wc_ZOqTJRDncadJVFy2CTIldvxIoeYSimDk7WClYeWs_lt2It9tJwt5GEDnP3MNoSZ931Vlvf4TLDfNnne8rRJqzONFQt8hKE_Kw1k5vgAI9EPYJKhLi17m1Bd1xBgKToRZynaNO-zpyXS5VCITm26iEUE7ik5J-KhvTjgElAAds8aIQd5Ms1J3W5iowHu',
    tags: ['Heritage walks', 'Filter chai spots', 'Art galleries'],
    match: '94%',
    matchBg: 'bg-tertiary text-on-tertiary',
    status: 'Available this week',
    statusDot: 'bg-tertiary',
  },
  {
    id: 'p2',
    name: 'Arjun M.',
    role: 'Street Food Expert · Bandra',
    avatar: 'https://lh3.googleusercontent.com/aida/AEtjO1UvDxu9a1SN0IFEcKN9qpI3wijV8Jy9cBJ-t877vR9MHw-_3Tkxs1QOeK6rT2wc_ZOqTJRDncadJVFy2CTIldvxIoeYSimDk7WClYeWs_lt2It9tJwt5GEDnP3MNoSZ931Vlvf4TLDfNnne8rRJqzONFQt8hKE_Kw1k5vgAI9EPYJKhLi17m1Bd1xBgKToRZynaNO-zpyXS5VCITm26iEUE7ik5J-KhvTjgElAAds8aIQd5Ms1J3W5iowHu',
    tags: ['Night food trails', 'Khau galli', 'Vada pav culture'],
    match: '91%',
    matchBg: 'bg-primary text-on-primary',
    status: 'Available evenings',
    statusDot: 'bg-tertiary',
  },
  {
    id: 'p3',
    name: 'Meera K.',
    role: 'Craft Documenter · Dharavi',
    avatar: 'https://lh3.googleusercontent.com/aida/AEtjO1UvDxu9a1SN0IFEcKN9qpI3wijV8Jy9cBJ-t877vR9MHw-_3Tkxs1QOeK6rT2wc_ZOqTJRDncadJVFy2CTIldvxIoeYSimDk7WClYeWs_lt2It9tJwt5GEDnP3MNoSZ931Vlvf4TLDfNnne8rRJqzONFQt8hKE_Kw1k5vgAI9EPYJKhLi17m1Bd1xBgKToRZynaNO-zpyXS5VCITm26iEUE7ik5J-KhvTjgElAAds8aIQd5Ms1J3W5iowHu',
    tags: ['Pottery', 'Textile art', 'Community spaces'],
    match: '87%',
    matchBg: 'bg-primary-fixed text-on-primary-fixed',
    status: 'Weekends only',
    statusDot: 'bg-secondary',
  },
];

export default function MeetLocalsSection() {
  return (
    <section className="w-full px-5 py-space-xl bg-surface-container-low">
      <div className="max-w-7xl mx-auto flex flex-col gap-8">
        {/* Header */}
        <motion.div
          className="flex flex-col md:flex-row md:items-end justify-between gap-4"
          variants={fadeUp}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          <div className="flex flex-col gap-2">
            <span className="font-label-sm text-label-sm tracking-widest uppercase text-primary font-bold">
              Meet Locals
            </span>
            <h2 className="font-[Manrope] text-[28px] md:text-[36px] leading-[1.1] tracking-[-0.03em] font-bold text-on-surface">
              RANDOM MEETUP.
              <br />
              <span className="font-[Newsreader] italic font-normal text-on-surface-variant">
                curated by affinity.
              </span>
            </h2>
          </div>
          <p className="font-body-md text-body-md text-on-surface-variant max-w-sm">
            Not chance. Not forced. Matched based on what you love about Mumbai, and connected
            through a shared moment in the city.
          </p>
        </motion.div>

        {/* Profile cards */}
        <motion.div
          className="grid grid-cols-1 md:grid-cols-3 gap-5"
          variants={staggerContainer}
          initial="hidden"
          whileInView="visible"
          viewport={viewportOnce}
        >
          {meetupProfiles.map((profile) => (
            <motion.div
              key={profile.id}
              className="rounded-2xl bg-surface-container-lowest overflow-hidden shadow-sm p-5 flex flex-col gap-4"
              variants={scaleIn}
              whileHover={{
                y: -6,
                boxShadow: '0 16px 32px -6px rgba(46,39,36,0.14)',
                transition: { duration: 0.28, ease: [0.22, 1, 0.36, 1] },
              }}
            >
              {/* Profile header */}
              <div className="flex items-center gap-3">
                <div className="relative">
                  <img
                    src={profile.avatar}
                    alt={profile.name}
                    className="w-14 h-14 rounded-full object-cover ring-2 ring-surface-container"
                  />
                  <motion.div
                    className={`absolute bottom-0 right-0 w-3.5 h-3.5 rounded-full ${profile.statusDot} ring-2 ring-surface-container-lowest`}
                    animate={{ scale: [1, 1.3, 1] }}
                    transition={{ repeat: Infinity, duration: 2, ease: 'easeInOut' }}
                  />
                </div>
                <div className="flex flex-col">
                  <span className="font-headline-sm text-headline-sm text-on-surface">{profile.name}</span>
                  <span className="font-label-md text-label-md text-on-surface-variant">{profile.role}</span>
                </div>
                <div className={`ml-auto px-2.5 py-1 rounded-full font-label-sm text-label-sm font-bold ${profile.matchBg}`}>
                  {profile.match}
                </div>
              </div>

              {/* Interest tags */}
              <div className="flex flex-wrap gap-2">
                {profile.tags.map((tag) => (
                  <span
                    key={tag}
                    className="px-2.5 py-1 rounded-full bg-secondary-container text-on-secondary-container font-label-sm text-label-sm"
                  >
                    {tag}
                  </span>
                ))}
              </div>

              {/* Status */}
              <div className="flex items-center gap-1.5">
                <div className={`w-2 h-2 rounded-full ${profile.statusDot}`} />
                <span className="font-label-md text-label-md text-on-surface-variant">{profile.status}</span>
              </div>

              {/* CTA */}
              <motion.button
                className="w-full py-3 rounded-xl bg-primary-container text-on-primary font-label-md text-label-md flex items-center justify-center gap-1.5 hover:bg-primary transition-colors cursor-pointer"
                whileHover={{ scale: 1.02 }}
                whileTap={{ scale: 0.97 }}
                transition={{ duration: 0.18 }}
              >
                <span className="material-symbols-outlined text-[18px]">people</span>
                Request meetup
              </motion.button>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
