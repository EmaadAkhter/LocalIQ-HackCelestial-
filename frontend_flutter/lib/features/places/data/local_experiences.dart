import '../../context/domain/context_models.dart';
import '../../places/domain/place.dart';

/// The bundled experience catalogue. One or more experiences hang off each
/// place, mirroring how a real catalogue models "what you can do there"
/// separately from "where it is".
const localExperiences = <Experience>[
  // ---------------------------------------------------------- Bastion Cafe
  Experience(
    id: 'exp-irani-trail',
    placeId: 'place-bastion-cafe',
    title: 'Irani Café Trail',
    tagline: 'Bun maska, cutting chai and Art Deco history',
    description:
        'A progression through Fort\'s surviving Irani rooms: the bun maska, '
        'the second cup of chai, and the marble-and-teak interiors that made '
        'this room a film set.',
    category: ExperienceCategory.food,
    secondaryCategory: 'Local institution',
    imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 40,
    minimumMinutes: 25,
    typicalSpend: 450,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 94,
    touristScore: 42,
    highlights: [
      'Fully indoor, so weather never interrupts it',
      'Eight other Fort options are a short walk away',
      'Sits comfortably inside a mid-range food budget',
    ],
    practicalTip:
        'Order the bun maska first, then give the chai a full pour before '
        'tasting the food. That is the whole ritual.',
  ),
  Experience(
    id: 'exp-bastion-quick-plate',
    placeId: 'place-bastion-cafe',
    title: 'Quick Irani Plate',
    tagline: 'The 25-minute version of the café',
    description:
        'A trimmed visit: one dish, one beverage, no lingering. Built for '
        'short windows where a full sit-down would not fit.',
    category: ExperienceCategory.food,
    secondaryCategory: 'Quick stop',
    imageUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 25,
    minimumMinutes: 20,
    flexibleTiming: true,
    typicalSpend: 260,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 88,
    touristScore: 30,
    highlights: [
      'Fits a one-hour window including travel',
      'Shortest meaningful food stop in the set',
    ],
    practicalTip: 'Order at the counter and take the corner table upstairs.',
  ),

  // ----------------------------------------------------- Jehangir / Kala Ghoda
  Experience(
    id: 'exp-jehangir-visit',
    placeId: 'place-jehangir',
    title: 'Jehangir Art Gallery',
    tagline: 'A colonial hall, rotated shows, ₹10',
    description:
        'India\'s oldest public art gallery in a stone hall from 1852. Two '
        'rooms of rotating work, air-conditioned, and almost impossible to '
        'rush.',
    category: ExperienceCategory.art,
    secondaryCategory: 'Gallery',
    imageUrl: 'https://images.unsplash.com/photo-1578926288207-a90a5366759d?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 35,
    minimumMinutes: 25,
    typicalSpend: 10,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 86,
    touristScore: 48,
    highlights: [
      'Indoor, dry and close to other Fort stops',
      '₹10 entry — effectively free',
      'Stackable with a café stop nearby',
    ],
    practicalTip:
        'The café inside charges tourist prices. The one across the road does '
        'not.',
  ),
  Experience(
    id: 'exp-kala-ghoda-walk',
    placeId: 'place-kala-ghoda',
    title: 'Kala Ghoda Art Walk',
    tagline: 'Murals, studios and open galleries in one block',
    description:
        'A self-guided loop through Fort\'s densest art block: the national '
        'gallery, the animal sculptures, and the studios that open their doors '
        'on the weekend.',
    category: ExperienceCategory.art,
    secondaryCategory: 'Walking route',
    imageUrl: 'https://images.unsplash.com/photo-1577083552431-6e5fd01988ec?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 50,
    minimumMinutes: 30,
    typicalSpend: 200,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Self-guided',
    localScore: 90,
    touristScore: 62,
    highlights: [
      'Free outdoors — the spend is optional',
      'Dense, so it absorbs a short window well',
      'Overlaps with the gallery, so they stack',
    ],
    practicalTip:
        'Start at the Maharashtra Police building murals and walk east; you '
        'avoid the photo queue at the tiger sculpture.',
  ),

  // ------------------------------------------------------------------ CSMVS
  Experience(
    id: 'exp-csmvs-deep-dive',
    placeId: 'place-csmvs',
    title: 'CSMVS Deep Dive',
    tagline: 'The full museum, properly seen',
    description:
        'The miniature painting wing, the Indus Valley gallery and the natural '
        'history halls. A serious half-day visit, not a stop.',
    category: ExperienceCategory.culture,
    secondaryCategory: 'Museum',
    imageUrl: 'https://images.unsplash.com/photo-1554907984-15263bfd63bd?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 90,
    minimumMinutes: 60,
    typicalSpend: 500,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Timed entry',
    localScore: 74,
    touristScore: 78,
    highlights: [
      'Fully indoor and wheelchair accessible',
      'The strongest culture option in the set',
    ],
    practicalTip: 'The miniature gallery closes 30 minutes before the doors. '
        'Go there first.',
  ),
  Experience(
    id: 'exp-csmvs-highlights',
    placeId: 'place-csmvs',
    title: 'CSMVS Highlights Tour',
    tagline: 'Three rooms, 45 minutes, done properly',
    description:
        'A compressed route through the strongest galleries: miniatures, '
        'Buddhist sculpture and the city-model room.',
    category: ExperienceCategory.culture,
    secondaryCategory: 'Museum highlights',
    imageUrl: 'https://images.unsplash.com/photo-1554907984-15263bfd63bd?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 45,
    minimumMinutes: 35,
    typicalSpend: 500,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Timed entry',
    localScore: 78,
    touristScore: 70,
    highlights: [
      'The only museum here that fits a two-hour window',
      'Indoor, so it holds up in any weather',
    ],
    practicalTip: 'Buy the ₹100 "highlights" ticket at the gate if available.',
  ),

  // --------------------------------------------------------------- Colaba
  Experience(
    id: 'exp-colaba-loop',
    placeId: 'place-colaba-causeway',
    title: 'Colaba Causeway Loop',
    tagline: 'Bazaar lanes, tailors and quick plates',
    description:
        'A compressed walk down the causeway and across Bazaar Road, ending '
        'at the arcade. Busy, outdoors, and best in dry weather.',
    category: ExperienceCategory.shopping,
    secondaryCategory: 'Bazaar',
    imageUrl: 'https://images.unsplash.com/photo-1555529902-5261145633bf?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 50,
    minimumMinutes: 30,
    typicalSpend: 600,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Walk-in',
    localScore: 58,
    touristScore: 88,
    highlights: ['Food and shopping in one walk', 'Open until late'],
    practicalTip: 'Bazaar Road is the food lane; the causeway itself is craft '
        'stalls and tailors.',
  ),
  Experience(
    id: 'exp-gateway-precinct',
    placeId: 'place-gateway',
    title: 'Gateway Precinct',
    tagline: 'The arch, the colonnade and the Taj view',
    description:
        'An hour around the Apollo Bunder plaza, including the colonnade where '
        'you can stay out of the rain and still see the water.',
    category: ExperienceCategory.heritage,
    secondaryCategory: 'Landmark',
    imageUrl: 'https://images.unsplash.com/photo-1587474260584-136574528ed5?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 30,
    minimumMinutes: 20,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Open access',
    localScore: 52,
    touristScore: 97,
    highlights: ['Free', 'Flat, level ground', 'The colonnade stays dry-ish'],
    practicalTip: 'Stand under the colonnade at the seaward end for the best '
        'Taj Mahal Palace view.',
  ),
  Experience(
    id: 'exp-sassoon-auction',
    placeId: 'place-sassoon-dock',
    title: 'Sassoon Dock Fish Auction',
    tagline: 'Mumbai\'s working harbour, before the crowds',
    description:
        'Walk the auction galleries while the trawlers are still unloading. '
        'Loud, salt-heavy, and the most genuinely local morning in the city.',
    category: ExperienceCategory.localLife,
    secondaryCategory: 'Harbour',
    imageUrl: 'https://images.unsplash.com/photo-1544551763-46a013bb70d5?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 40,
    minimumMinutes: 30,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Public viewing',
    localScore: 92,
    touristScore: 34,
    highlights: ['Free', 'Almost no other visitors'],
    practicalTip: 'Be there before 09:00. After 11:00 the galleries are closed '
        'to the public.',
  ),

  // ----------------------------------------------------------- Waterfront
  Experience(
    id: 'exp-marine-sunset',
    placeId: 'place-marine-drive',
    title: 'Marine Drive Sunset Walk',
    tagline: 'The Queen\'s Necklace at golden hour',
    description:
        'A stretch of the Nariman Point esplanade timed so the lights come on '
        'as you reach the end. Entirely outdoors.',
    category: ExperienceCategory.nature,
    secondaryCategory: 'Waterfront',
    imageUrl: 'https://images.unsplash.com/photo-1529253355930-ddbe423a2d60?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 45,
    minimumMinutes: 25,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Open access',
    localScore: 70,
    touristScore: 94,
    highlights: ['Free', 'Flat promenade', 'The single best sunset in the set'],
    practicalTip: 'Start at Nariman Point and walk south — the lights come on '
        'at the Chowpatty end.',
  ),
  Experience(
    id: 'exp-worli-seaface',
    placeId: 'place-worli-sea-face',
    title: 'Worli Sea Face Walk',
    tagline: 'Wide promenade, Sea Link views',
    description:
        'An open walk facing the Bandra–Worli Sea Link. Long, flat and free — '
        'the reason is the journey, not the destination.',
    category: ExperienceCategory.nature,
    secondaryCategory: 'Waterfront',
    imageUrl: 'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 40,
    minimumMinutes: 25,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Open access',
    localScore: 66,
    touristScore: 64,
    highlights: ['Free', 'Level and wide', 'Sea Link views the whole way'],
    practicalTip: 'Only worth it if you already are on that side of the city.',
  ),
  Experience(
    id: 'exp-haji-ali',
    placeId: 'place-haji-ali',
    title: 'Haji Ali Causeway Walk',
    tagline: 'Tidal causeway to a 15th-century shrine',
    description:
        'Cross the causeway when the tide allows, visit the dargah, and return. '
        'Long exposure, exposed, and timing-dependent.',
    category: ExperienceCategory.heritage,
    secondaryCategory: 'Shrine',
    imageUrl: 'https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 50,
    minimumMinutes: 35,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Tide dependent',
    localScore: 64,
    touristScore: 84,
    highlights: ['Free entry', 'Unmatched sea view'],
    practicalTip: 'Check the tide table before you leave — the causeway '
        'submerges fast.',
  ),

  // -------------------------------------------------------------- Gamdevi
  Experience(
    id: 'exp-mani-bhavan',
    placeId: 'place-mani-bhavan',
    title: 'Mani Bhavan Museum',
    tagline: 'Gandhi\'s home, preserved',
    description:
        'Four rooms of the house Gandhi lived in through the freedom movement, '
        'including the room he was arrested in.',
    category: ExperienceCategory.history,
    secondaryCategory: 'Memorial museum',
    imageUrl: 'https://images.unsplash.com/photo-1526772662000-3f88f10405ff?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 45,
    minimumMinutes: 30,
    typicalSpend: 20,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 88,
    touristScore: 52,
    highlights: [
      'Indoor, so it works in any weather',
      'The cheapest meaningful stop in the set',
      'Quiet enough for a family visit',
    ],
    practicalTip: 'Aga Khan Palace tickets are issued at the gate — keep the '
        'confirmation email handy.',
  ),

  // -------------------------------------------------------------- Byculla
  Experience(
    id: 'exp-lad-museum',
    placeId: 'place-bhau-daji-lad',
    title: 'Dr. Bhau Daji Lad Museum',
    tagline: 'Restored Victorian town hall, city-scale models',
    description:
        'The restored municipal museum: industrial-age Mumbai, a working '
        'diorama, and the finest textile collection in the country.',
    category: ExperienceCategory.culture,
    secondaryCategory: 'Museum',
    imageUrl: 'https://images.unsplash.com/photo-1564393144196-09886b27d386?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 50,
    minimumMinutes: 35,
    typicalSpend: 100,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 84,
    touristScore: 46,
    highlights: [
      'Indoor and wheelchair accessible',
      '₹100 for the best-value culture stop in the set',
    ],
    practicalTip: 'The restored industrial hall alone justifies the trip.',
  ),

  // ---------------------------------------------------------------- Bandra
  Experience(
    id: 'exp-bandra-fort',
    placeId: 'place-bandra-fort',
    title: 'Bandra Fort Ramparts',
    tagline: 'Portuguese sea fort on a Bandra headland',
    description:
        'Walk the ramparts of Castella de Aguada for the view down the western '
        'coast. Short, steep in places, best in the late afternoon.',
    category: ExperienceCategory.heritage,
    secondaryCategory: 'Photography',
    imageUrl: 'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 30,
    minimumMinutes: 20,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.weatherSensitive,
    bookingNote: 'Open access',
    localScore: 82,
    touristScore: 54,
    highlights: ['Free', 'The best sunset photography in the city'],
    practicalTip: 'Pair it with Mount Mary and Pali Hill if you have a whole '
        'afternoon on that side.',
  ),
  Experience(
    id: 'exp-candies-quick',
    placeId: 'place-candies',
    title: 'Candies Quick Plate',
    tagline: 'Pali Hill sandwiches and thick shakes',
    description:
        'A short, warm, family-friendly food stop: sandwich, shake, out the '
        'door in under half an hour.',
    category: ExperienceCategory.food,
    secondaryCategory: 'Cafe',
    imageUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 45,
    minimumMinutes: 25,
    typicalSpend: 300,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Walk-in',
    localScore: 86,
    touristScore: 34,
    highlights: ['Indoor and family friendly', '₹300 for two', 'Open very late'],
    practicalTip: 'The Pali Hill branch has a much smaller queue after 16:00.',
  ),
  Experience(
    id: 'exp-mount-mary',
    placeId: 'place-mount-mary',
    title: 'Mount Mary Basilica',
    tagline: 'Hilltop Gothic basilica and courtyard',
    description:
        'A quiet walk up the hill to a 1904 basilica, then the courtyard and '
        'the view back over Worli.',
    category: ExperienceCategory.culture,
    secondaryCategory: 'Architecture',
    imageUrl: 'https://images.unsplash.com/photo-1473177104440-ffee2f376098?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 25,
    minimumMinutes: 20,
    typicalSpend: 0,
    weatherSuitability: WeatherSuitability.sheltered,
    bookingNote: 'Open access',
    localScore: 80,
    touristScore: 48,
    highlights: ['Free', 'Sheltered from light rain', 'Quiet'],
    practicalTip: 'Basilica rules: no photography inside the nave.',
  ),

  // ---------------------------------------------------------------- Colaba
  Experience(
    id: 'exp-the-table-dinner',
    placeId: 'place-the-table',
    title: 'The Table Dinner',
    tagline: 'Seasonal European tasting in a bungalow',
    description:
        'A long, unhurried meal in a restored Colaba bungalow. Excellent, and '
        'a poor fit for a discovery window.',
    category: ExperienceCategory.food,
    secondaryCategory: 'Restaurant',
    imageUrl: 'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1200&q=80',
    activityMinutes: 70,
    minimumMinutes: 50,
    typicalSpend: 2400,
    weatherSuitability: WeatherSuitability.indoorOnly,
    bookingNote: 'Reservation',
    localScore: 62,
    touristScore: 76,
    highlights: ['Indoor and air-conditioned', 'Strong seasonal menu'],
    practicalTip: 'The weekday lunch set is roughly half the à la carte cost.',
  ),
];
