import '../../context/domain/context_models.dart';
import '../../places/domain/place.dart';

/// Opening-hours shorthand. Values are minutes from midnight.
List<IntRange> _open(int open, int close) => [IntRange(open, close)];

/// Builds a weekly schedule. `0` means "no closure on that weekday".
OpeningHours _hours({
  required int openMinutes,
  required int closeMinutes,
  int? weekdayOpen,
  int? weekdayClose,
  int closedWeekday = 0,
  required String note,
}) {
  final map = <int, List<IntRange>>{};
  const all = [1, 2, 3, 4, 5, 6, 7];
  for (final day in all) {
    if (day == closedWeekday) continue;
    final o = (day <= 5 && weekdayOpen != null) ? weekdayOpen : openMinutes;
    final c = (day <= 5 && weekdayClose != null) ? weekdayClose : closeMinutes;
    map[day] = _open(o, c);
  }
  return OpeningHours(weekly: map, specialNote: note);
}

const _fort = GeoPoint(latitude: 18.9322, longitude: 72.8316);
const _kalaGhoda = GeoPoint(latitude: 18.9288, longitude: 72.8312);
const _gamdevi = GeoPoint(latitude: 18.9598, longitude: 72.8113);
const _colaba = GeoPoint(latitude: 18.9217, longitude: 72.8328);
const _marineDrive = GeoPoint(latitude: 18.9432, longitude: 72.8236);
const _apolloBunder = GeoPoint(latitude: 18.9220, longitude: 72.8347);
const _worli = GeoPoint(latitude: 19.0089, longitude: 72.8156);
const _hajiAli = GeoPoint(latitude: 18.9827, longitude: 72.8089);
const _bandra = GeoPoint(latitude: 19.0423, longitude: 72.8184);
const _paliHill = GeoPoint(latitude: 19.0669, longitude: 72.8296);
const _mountMary = GeoPoint(latitude: 19.0466, longitude: 72.8222);
const _byculla = GeoPoint(latitude: 18.9790, longitude: 72.8346);
const _sassoon = GeoPoint(latitude: 18.9078, longitude: 72.8254);
const _mumbaiCsmvs = GeoPoint(latitude: 18.9269, longitude: 72.8326);

const _imgIrani =
    'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=1200&q=80';
const _imgArtWalk =
    'https://images.unsplash.com/photo-1577083552431-6e5fd01988ec?auto=format&fit=crop&w=1200&q=80';
const _imgMuseum =
    'https://images.unsplash.com/photo-1526772662000-3f88f10405ff?auto=format&fit=crop&w=1200&q=80';
const _imgMarket =
    'https://images.unsplash.com/photo-1555529902-5261145633bf?auto=format&fit=crop&w=1200&q=80';
const _imgGallery =
    'https://images.unsplash.com/photo-1578926288207-a90a5366759d?auto=format&fit=crop&w=1200&q=80';
const _imgMarine =
    'https://images.unsplash.com/photo-1529253355930-ddbe423a2d60?auto=format&fit=crop&w=1200&q=80';
const _imgGateway =
    'https://images.unsplash.com/photo-1587474260584-136574528ed5?auto=format&fit=crop&w=1200&q=80';
const _imgMuseumBig =
    'https://images.unsplash.com/photo-1554907984-15263bfd63bd?auto=format&fit=crop&w=1200&q=80';
const _imgSeaFace =
    'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80';
const _imgDargah =
    'https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80';
const _imgFort =
    'https://images.unsplash.com/photo-1524492412937-b28074a5d7da?auto=format&fit=crop&w=1200&q=80';
const _imgCafe =
    'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=1200&q=80';
const _imgChurch =
    'https://images.unsplash.com/photo-1473177104440-ffee2f376098?auto=format&fit=crop&w=1200&q=80';
const _imgLad =
    'https://images.unsplash.com/photo-1564393144196-09886b27d386?auto=format&fit=crop&w=1200&q=80';
const _imgDock =
    'https://images.unsplash.com/photo-1544551763-46a013bb70d5?auto=format&fit=crop&w=1200&q=80';
const _imgRestaurant =
    'https://images.unsplash.com/photo-1414235077428-338989a2e8c0?auto=format&fit=crop&w=1200&q=80';

/// The bundled place dataset. Shape matches `GET /places`, so replacing this
/// with the remote repository requires no model changes.
final List<Place> localPlaces = [
  // ---------------------------------------------------------------- Fort
  Place(
    id: 'place-bastion-cafe',
    name: 'Bastion Cafe',
    category: ExperienceCategory.food,
    address: '12/24, Barrister Nath Pai Marg, Fort',
    area: 'Bastion, Fort',
    centre: _fort,
    heroImageUrl: _imgIrani,
    imageUrls: [_imgCafe],
    openingHours: OpeningHours(
      weekly: {
        1: _open(420, 1140),
        2: _open(420, 1140),
        3: _open(420, 1140),
        4: _open(420, 1140),
        5: _open(420, 1140),
        6: _open(420, 1200),
        7: _open(420, 1200),
      },
      specialNote: 'Iconic Art Deco interiors, walk-ins only.',
    ),
    accessibility: AccessibilityProfile(
      maxWalkingMinutes: 6,
      seatingAvailable: true,
    ),
    rating: 4.7,
    reviewCount: 2400,
    priceLevel: 2,
    typicalSpend: 450,
    crowdLevel: CrowdLevel.moderate,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'A 1930s basement institution serving Irani chai and berry buns.',
  ),
  Place(
    id: 'place-jehangir',
    name: 'Jehangir Art Gallery',
    category: ExperienceCategory.art,
    address: 'NG Machindra Marg, Kala Ghoda, Fort',
    area: 'Kala Ghoda, Fort',
    centre: _kalaGhoda,
    heroImageUrl: _imgGallery,
    imageUrls: [_imgGallery],
    openingHours: OpeningHours(
      weekly: {
        1: _open(660, 1080),
        2: _open(660, 1080),
        3: _open(660, 1080),
        4: _open(660, 1080),
        5: _open(660, 1080),
        6: _open(660, 1080),
        7: _open(0, 0),
      },
      specialNote: 'Closed Mondays. ₹10 entry.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      maxWalkingMinutes: 8,
      restrooms: false,
    ),
    rating: 4.6,
    reviewCount: 1400,
    priceLevel: 0,
    typicalSpend: 10,
    crowdLevel: CrowdLevel.moderate,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'India\'s oldest public art gallery, in a 1852 stone hall.',
  ),
  Place(
    id: 'place-kala-ghoda',
    name: 'Kala Ghoda Arts District',
    category: ExperienceCategory.art,
    address: 'Kala Ghoda, Fort',
    area: 'Kala Ghoda, Fort',
    centre: _kalaGhoda,
    heroImageUrl: _imgArtWalk,
    imageUrls: [_imgArtWalk],
    openingHours: OpeningHours(weekly: {1: _open(0, 1440), 2: _open(0, 1440), 3: _open(0, 1440), 4: _open(0, 1440), 5: _open(0, 1440), 6: _open(0, 1440), 7: _open(0, 1440)}),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: true,
      maxWalkingMinutes: 25,
    ),
    rating: 4.6,
    reviewCount: 2100,
    priceLevel: 0,
    typicalSpend: 200,
    crowdLevel: CrowdLevel.busy,
    indoor: false,
    localFavourite: true,
    bookingRequired: false,
    summary: 'Mumbai\'s densest public-art block: studios, murals and open galleries.',
  ),
  Place(
    id: 'place-csmvs',
    name: 'CSMVS',
    category: ExperienceCategory.culture,
    address: 'CSMVS Marg, Fort',
    area: 'Fort',
    centre: _mumbaiCsmvs,
    heroImageUrl: _imgMuseumBig,
    imageUrls: [_imgMuseumBig],
    openingHours: OpeningHours(
      weekly: {
        1: _open(615, 1080),
        2: _open(615, 1080),
        3: _open(615, 1080),
        4: _open(615, 1080),
        5: _open(615, 1080),
        6: _open(615, 1080),
        7: _open(615, 1080),
      },
      specialNote: 'Timed entry, closed for lunch 14:00–14:30.',
    ),
    accessibility: AccessibilityProfile(maxWalkingMinutes: 20),
    rating: 4.7,
    reviewCount: 3400,
    priceLevel: 2,
    typicalSpend: 500,
    crowdLevel: CrowdLevel.moderate,
    indoor: true,
    localFavourite: false,
    bookingRequired: true,
    summary: 'The Prince of Wales Museum: miniatures, Indus Valley and natural history.',
  ),

  // ------------------------------------------------------------- Colaba
  Place(
    id: 'place-colaba-causeway',
    name: 'Colaba Causeway',
    category: ExperienceCategory.shopping,
    address: 'Colaba Causeway, Colaba',
    area: 'Colaba',
    centre: _colaba,
    heroImageUrl: _imgMarket,
    imageUrls: [_imgMarket],
    openingHours: OpeningHours(weekly: {1: _open(600, 1320), 2: _open(600, 1320), 3: _open(600, 1320), 4: _open(600, 1320), 5: _open(600, 1320), 6: _open(600, 1320), 7: _open(600, 1320)}),
    accessibility: AccessibilityProfile(
      stepFree: true,
      maxWalkingMinutes: 20,
    ),
    rating: 4.1,
    reviewCount: 5200,
    priceLevel: 2,
    typicalSpend: 600,
    crowdLevel: CrowdLevel.veryBusy,
    indoor: false,
    localFavourite: false,
    bookingRequired: false,
    summary: 'Open-air bazaar of tailors, souvenirs and quick street plates.',
  ),
  Place(
    id: 'place-gateway',
    name: 'Gateway of India',
    category: ExperienceCategory.heritage,
    address: 'Apollo Bunder, Colaba',
    area: 'Apollo Bunder',
    centre: _apolloBunder,
    heroImageUrl: _imgGateway,
    imageUrls: [_imgGateway],
    openingHours: OpeningHours(weekly: {1: _open(0, 1440), 2: _open(0, 1440), 3: _open(0, 1440), 4: _open(0, 1440), 5: _open(0, 1440), 6: _open(0, 1440), 7: _open(0, 1440)}),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: true,
      maxWalkingMinutes: 18,
    ),
    rating: 4.5,
    reviewCount: 22000,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.veryBusy,
    indoor: false,
    localFavourite: false,
    bookingRequired: false,
    summary: '1911 basalt arch marking the old harbour entrance.',
  ),
  Place(
    id: 'place-sassoon-dock',
    name: 'Sassoon Dock',
    category: ExperienceCategory.localLife,
    address: 'Sassoon Dock, Colaba',
    area: 'Colaba',
    centre: _sassoon,
    heroImageUrl: _imgDock,
    imageUrls: [_imgDock],
    openingHours: OpeningHours(
      weekly: {
        1: _open(300, 780),
        2: _open(300, 780),
        3: _open(300, 780),
        4: _open(300, 780),
        5: _open(300, 780),
        6: _open(300, 780),
        7: _open(300, 780),
      },
      specialNote: 'Public viewing of the auction only before 13:00.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: false,
      maxWalkingMinutes: 12,
    ),
    rating: 4.2,
    reviewCount: 900,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.quiet,
    indoor: false,
    localFavourite: true,
    bookingRequired: false,
    summary: 'Mumbai\'s oldest working harbour, open for the dawn fish auction.',
  ),

  // --------------------------------------------------------- Waterfront
  Place(
    id: 'place-marine-drive',
    name: 'Marine Drive',
    category: ExperienceCategory.nature,
    address: 'Netaji Subhash Chandra Bose Road, Nariman Point',
    area: 'Marine Drive',
    centre: _marineDrive,
    heroImageUrl: _imgMarine,
    imageUrls: [_imgMarine],
    openingHours: OpeningHours(weekly: {1: _open(0, 1440), 2: _open(0, 1440), 3: _open(0, 1440), 4: _open(0, 1440), 5: _open(0, 1440), 6: _open(0, 1440), 7: _open(0, 1440)}),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: true,
      maxWalkingMinutes: 30,
    ),
    rating: 4.7,
    reviewCount: 18000,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.busy,
    indoor: false,
    localFavourite: false,
    bookingRequired: false,
    summary: 'The Queen\'s Necklace — a 3.6 km esplanade curving into Back Bay.',
  ),
  Place(
    id: 'place-worli-sea-face',
    name: 'Worli Sea Face',
    category: ExperienceCategory.nature,
    address: 'Dr Annie Besant Road, Worli',
    area: 'Worli',
    centre: _worli,
    heroImageUrl: _imgSeaFace,
    imageUrls: [_imgSeaFace],
    openingHours: OpeningHours(weekly: {1: _open(0, 1440), 2: _open(0, 1440), 3: _open(0, 1440), 4: _open(0, 1440), 5: _open(0, 1440), 6: _open(0, 1440), 7: _open(0, 1440)}),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: true,
      maxWalkingMinutes: 30,
    ),
    rating: 4.4,
    reviewCount: 3200,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.moderate,
    indoor: false,
    localFavourite: false,
    bookingRequired: false,
    summary: 'A long open promenade facing the Bandra–Worli Sea Link.',
  ),
  Place(
    id: 'place-haji-ali',
    name: 'Haji Ali Dargah',
    category: ExperienceCategory.heritage,
    address: 'Haji Ali Dargah Road, Worli',
    area: 'Worli',
    centre: _hajiAli,
    heroImageUrl: _imgDargah,
    imageUrls: [_imgDargah],
    openingHours: OpeningHours(
      weekly: {
        1: _open(360, 1320),
        2: _open(360, 1320),
        3: _open(360, 1320),
        4: _open(360, 1320),
        5: _open(360, 1320),
        6: _open(360, 1320),
        7: _open(360, 1320),
      },
      specialNote: 'The causeway submerges at high tide — check timings.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: false,
      maxWalkingMinutes: 20,
      seatingAvailable: false,
    ),
    rating: 4.5,
    reviewCount: 14000,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.busy,
    indoor: false,
    localFavourite: false,
    bookingRequired: false,
    summary: 'A 15th-century island shrine reached by a tidal causeway.',
  ),

  // ------------------------------------------------------------ Gamdevi
  Place(
    id: 'place-mani-bhavan',
    name: 'Mani Bhavan',
    category: ExperienceCategory.history,
    address: 'Laburnum Road, Gamdevi',
    area: 'Gamdevi',
    centre: _gamdevi,
    heroImageUrl: _imgMuseum,
    imageUrls: [_imgMuseum],
    openingHours: _hours(
      openMinutes: 570,
      closeMinutes: 1080,
      weekdayOpen: 570,
      weekdayClose: 1080,
      closedWeekday: 7,
      note: 'Closed Sundays.',
    ),
    accessibility: AccessibilityProfile(
      maxWalkingMinutes: 10,
      restrooms: false,
    ),
    rating: 4.5,
    reviewCount: 1200,
    priceLevel: 0,
    typicalSpend: 20,
    crowdLevel: CrowdLevel.quiet,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'Gandhi\'s 1918–1931 residence, preserved as a memorial museum.',
  ),

  // ------------------------------------------------------------- Byculla
  Place(
    id: 'place-bhau-daji-lad',
    name: 'Dr. Bhau Daji Lad Museum',
    category: ExperienceCategory.culture,
    address: 'Victoria & Albert Museum, Byculla',
    area: 'Byculla',
    centre: _byculla,
    heroImageUrl: _imgLad,
    imageUrls: [_imgLad],
    openingHours: _hours(
      openMinutes: 600,
      closeMinutes: 1080,
      closedWeekday: 2,
      note: 'Closed Tuesdays.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: true,
      maxWalkingMinutes: 15,
    ),
    rating: 4.6,
    reviewCount: 1100,
    priceLevel: 1,
    typicalSpend: 100,
    crowdLevel: CrowdLevel.quiet,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'A restored Victorian town hall holding Mumbai\'s industrial-age city.',
  ),

  // -------------------------------------------------------------- Bandra
  Place(
    id: 'place-bandra-fort',
    name: 'Bandra Fort',
    category: ExperienceCategory.heritage,
    address: 'Bandstand, Bandra West',
    area: 'Bandra',
    centre: _bandra,
    heroImageUrl: _imgFort,
    imageUrls: [_imgFort],
    openingHours: _hours(
      openMinutes: 360,
      closeMinutes: 1140,
      closedWeekday: 7,
      note: 'Closed Mondays and Thursdays.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: false,
      maxWalkingMinutes: 15,
    ),
    rating: 4.5,
    reviewCount: 2600,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.moderate,
    indoor: false,
    localFavourite: true,
    bookingRequired: false,
    summary: 'Castella de Aguada, a Portuguese-era sea fort on a Bandra headland.',
  ),
  Place(
    id: 'place-candies',
    name: 'Candies',
    category: ExperienceCategory.food,
    address: 'Pali Hill, Bandra West',
    area: 'Pali Hill, Bandra',
    centre: _paliHill,
    heroImageUrl: _imgCafe,
    imageUrls: [_imgCafe],
    openingHours: _hours(
      openMinutes: 480,
      closeMinutes: 1560,
      note: 'Open late; expect a queue after 20:00.',
    ),
    accessibility: AccessibilityProfile(
      maxWalkingMinutes: 8,
    ),
    rating: 4.3,
    reviewCount: 2800,
    priceLevel: 1,
    typicalSpend: 300,
    crowdLevel: CrowdLevel.busy,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'A Pali Hill institution for quick sandwiches and thick shakes.',
  ),
  Place(
    id: 'place-mount-mary',
    name: 'Mount Mary Basilica',
    category: ExperienceCategory.culture,
    address: 'Basilica Road, Bandra West',
    area: 'Bandra West',
    centre: _mountMary,
    heroImageUrl: _imgChurch,
    imageUrls: [_imgChurch],
    openingHours: _hours(
      openMinutes: 360,
      closeMinutes: 1200,
      note: 'No photography inside the nave.',
    ),
    accessibility: AccessibilityProfile(
      wheelchairAccessible: false,
      stepFree: false,
      maxWalkingMinutes: 12,
    ),
    rating: 4.6,
    reviewCount: 1900,
    priceLevel: 0,
    typicalSpend: 0,
    crowdLevel: CrowdLevel.quiet,
    indoor: true,
    localFavourite: true,
    bookingRequired: false,
    summary: 'A hilltop Gothic basilica with a courtyard and organ.',
  ),

  // --------------------------------------------------------------- Other
  Place(
    id: 'place-the-table',
    name: 'The Table',
    category: ExperienceCategory.food,
    address: 'Apollo Bunder, Colaba',
    area: 'Colaba',
    centre: _colaba,
    heroImageUrl: _imgRestaurant,
    imageUrls: [_imgRestaurant],
    openingHours: _hours(
      openMinutes: 720,
      closeMinutes: 1620,
      note: 'Reservations recommended; weekday lunch set is half price.',
    ),
    accessibility: AccessibilityProfile(
      maxWalkingMinutes: 8,
    ),
    rating: 4.4,
    reviewCount: 1600,
    priceLevel: 3,
    typicalSpend: 2400,
    crowdLevel: CrowdLevel.moderate,
    indoor: true,
    localFavourite: false,
    bookingRequired: true,
    summary: 'Seasonal European dining in a restored Colaba bungalow.',
  ),
];
