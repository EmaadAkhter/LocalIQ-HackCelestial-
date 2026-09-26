import '../models/place.dart';

/// Curated Mumbai experiences used while the backend is not wired in.
///
/// Coordinates, costs, durations, hours and ratings mirror the FastAPI seed
/// dataset (`backend/data/mumbai_experiences.json`) so switching to the real
/// API is a drop-in change.
///
/// Images are deterministic placeholders (picsum.photos) and are replaced by
/// `image_url` from the API later.
abstract final class MockPlaces {
  MockPlaces._();

  static const List<Place> all = <Place>[
    Place(
      id: '1',
      name: 'Bandra Fort & Sea-Link View',
      category: PlaceCategory.outdoor,
      area: 'Bandra',
      lat: 19.0419,
      lng: 72.8194,
      avgCost: 200,
      durationMin: 90,
      openTime: '06:00',
      closeTime: '20:00',
      rating: 4.6,
      reviewCount: 3100,
      description:
          'A Portuguese-era sea fort on a headland, with the Bandra–Worli Sea '
          'Link curving into the horizon. Walk the ramparts, catch the sunset '
          'and watch the sea turn copper before the city lights come on.',
      imageUrl: 'https://picsum.photos/seed/localiq-bandra-fort/640/480',
      tags: <String>['fort', 'sunset', 'photography', 'sea-link'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.91,
    ),
    Place(
      id: '2',
      name: 'Candies Cafe',
      category: PlaceCategory.food,
      area: 'Bandra',
      lat: 19.0607,
      lng: 72.8352,
      avgCost: 300,
      durationMin: 45,
      openTime: '08:00',
      closeTime: '23:00',
      rating: 4.3,
      reviewCount: 1200,
      description:
          'A tiny Bandra institution for brass kettles on the table, thin '
          'margherita slices and homemade fig ice cream. Sit at the window '
          'counter and watch Linking Road go by.',
      imageUrl: 'https://picsum.photos/seed/localiq-candies/640/480',
      tags: <String>['cafe', 'dessert', 'budget-friendly'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.86,
    ),
    Place(
      id: '3',
      name: 'Mount Mary Basilica',
      category: PlaceCategory.culture,
      area: 'Bandra',
      lat: 19.0472,
      lng: 72.8215,
      avgCost: 0,
      durationMin: 20,
      openTime: '06:00',
      closeTime: '20:00',
      rating: 4.6,
      reviewCount: 3400,
      description:
          'A Gothic Revival basilica perched on Mount Mary, reached by a stepped '
          'lane. Visit at dusk for the lit facade, the sea panorama and the '
          'sounds of the bandstand below.',
      imageUrl: 'https://picsum.photos/seed/localiq-mount-mary/640/480',
      tags: <String>['spiritual', 'architecture', 'sunset'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.88,
    ),
    Place(
      id: '4',
      name: 'Elco Pani Puri & Chaat',
      category: PlaceCategory.food,
      area: 'Bandra',
      lat: 19.0505,
      lng: 72.8297,
      avgCost: 150,
      durationMin: 30,
      openTime: '11:00',
      closeTime: '23:00',
      rating: 4.5,
      reviewCount: 2600,
      description:
          'Crisp pani puris, five chutneys and a steel counter that has not '
          'changed since 1985. Go hungry, order loudly, share the samosa '
          'chaat.',
      imageUrl: 'https://picsum.photos/seed/localiq-elco/640/480',
      tags: <String>['street-food', 'chaat', 'vegetarian', 'budget'],
      accessibilityFlags: <String>['wheelchair-accessible', 'step-free'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.85,
    ),
    Place(
      id: '5',
      name: 'Gateway of India Sunrise',
      category: PlaceCategory.culture,
      area: 'Colaba',
      lat: 18.922,
      lng: 72.8347,
      avgCost: 250,
      durationMin: 60,
      openTime: '00:00',
      closeTime: '22:00',
      rating: 4.5,
      reviewCount: 7400,
      description:
          'The ceremonial arch at the harbour mouth, best at 6 AM when the '
          'causeway is empty and the Taj Palace catches the first light.',
      imageUrl: 'https://picsum.photos/seed/localiq-gateway/640/480',
      tags: <String>['landmark', 'harbour', 'photography', 'free'],
      accessibilityFlags: <String>['wheelchair-accessible', 'step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.7,
    ),
    Place(
      id: '6',
      name: 'Marine Drive Sunrise Walk',
      category: PlaceCategory.outdoor,
      area: 'Nariman Point',
      lat: 18.943,
      lng: 72.8225,
      avgCost: 100,
      durationMin: 90,
      openTime: '00:00',
      closeTime: '22:00',
      rating: 4.7,
      reviewCount: 5200,
      description:
          "A 3.6 km promenade that becomes the city's front porch at dawn: "
          'joggers, sea mist and the Art Deco skyline glowing pink.',
      imageUrl: 'https://picsum.photos/seed/localiq-marine-drive/640/480',
      tags: <String>['walking', 'sunrise', 'free', 'sea-face'],
      accessibilityFlags: <String>[],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.9,
    ),
    Place(
      id: '7',
      name: 'Leopold Cafe',
      category: PlaceCategory.food,
      area: 'Colaba',
      lat: 18.9062,
      lng: 72.8143,
      avgCost: 1200,
      durationMin: 90,
      openTime: '07:30',
      closeTime: '00:00',
      rating: 4.2,
      reviewCount: 6100,
      description:
          'Wooden booths, stained glass and draught beer since 1871. Order the '
          'chicken stroganoff and stay for one more round of people-watching.',
      imageUrl: 'https://picsum.photos/seed/localiq-leopold/640/480',
      tags: <String>['cafe', 'heritage', 'continental', 'beer'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.8,
    ),
    Place(
      id: '8',
      name: 'Britannia & Co.',
      category: PlaceCategory.food,
      area: 'Ballard Estate',
      lat: 18.9278,
      lng: 72.8413,
      avgCost: 900,
      durationMin: 75,
      openTime: '11:30',
      closeTime: '23:00',
      rating: 4.6,
      reviewCount: 2900,
      description:
          'A 112-year-old Parsi cafe with wood-panelled rooms, berry pulao, '
          'dhansak and the best lagan-nu-custard in the city.',
      imageUrl: 'https://picsum.photos/seed/localiq-britannia/640/480',
      tags: <String>['parsi', 'heritage', 'lunch', 'historic'],
      accessibilityFlags: <String>['wheelchair-accessible'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.92,
    ),
    Place(
      id: '9',
      name: 'Jeahangir Art Gallery',
      category: PlaceCategory.art,
      area: 'Kala Ghoda',
      lat: 18.9275,
      lng: 72.8305,
      avgCost: 300,
      durationMin: 90,
      openTime: '11:00',
      closeTime: '18:00',
      rating: 4.6,
      reviewCount: 1800,
      description:
          'Rotating contemporary shows inside a colonial gallery, steps from '
          'Kala Ghoda\'s murals, bookshops and Sunday flea stalls.',
      imageUrl: 'https://picsum.photos/seed/localiq-jehangir/640/480',
      tags: <String>['gallery', 'painting', 'heritage', 'rainy-day'],
      accessibilityFlags: <String>['wheelchair-accessible', 'step-free'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.89,
    ),
    Place(
      id: '10',
      name: 'Chandni Chowk Food Walk',
      category: PlaceCategory.food,
      area: 'Mohammed Ali Road',
      lat: 18.9567,
      lng: 72.834,
      avgCost: 500,
      durationMin: 90,
      openTime: '18:00',
      closeTime: '23:30',
      rating: 4.6,
      reviewCount: 4100,
      description:
          'Ramadan-lane staples all year: seekh kebabs, bhuna gosht, '
          'shawarma and a falooda finish. Go at 8 PM when the grills are hottest.',
      imageUrl: 'https://picsum.photos/seed/localiq-chandni/640/480',
      tags: <String>['street-food', 'non-veg', 'dinner', 'walking'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.mixed,
      localGemScore: 0.9,
    ),
    Place(
      id: '11',
      name: 'Banganga & Walkeshwar Walk',
      category: PlaceCategory.culture,
      area: 'Malabar Hill',
      lat: 18.9451,
      lng: 72.7922,
      avgCost: 150,
      durationMin: 90,
      openTime: '06:00',
      closeTime: '19:00',
      rating: 4.7,
      reviewCount: 1500,
      description:
          'An ancient stepwell temple on Walkeshwar Road, ringed by 19th-century '
          'heritage homes and morning bhajans. Old Mumbai at its quietest.',
      imageUrl: 'https://picsum.photos/seed/localiq-banganga/640/480',
      tags: <String>['heritage', 'temple', 'walking', 'hidden-gem'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.95,
    ),
    Place(
      id: '12',
      name: 'Prithvi Theatre',
      category: PlaceCategory.art,
      area: 'Juhu',
      lat: 19.1068,
      lng: 72.826,
      avgCost: 400,
      durationMin: 90,
      openTime: '10:00',
      closeTime: '22:00',
      rating: 4.7,
      reviewCount: 2200,
      description:
          "Shashi Kapoor's intimate 1978 theatre by the sea: plays, poetry "
          'nights and Prithvi Cafe chai before the show.',
      imageUrl: 'https://picsum.photos/seed/localiq-prithvi/640/480',
      tags: <String>['theatre', 'performance', 'cafe'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.indoor,
      localGemScore: 0.91,
    ),
    Place(
      id: '13',
      name: 'Chor Bazaar',
      category: PlaceCategory.shopping,
      area: 'Tardeo',
      lat: 18.9687,
      lng: 72.828,
      avgCost: 600,
      durationMin: 90,
      openTime: '10:00',
      closeTime: '19:30',
      rating: 4.2,
      reviewCount: 1300,
      description:
          "Mumbai's thief market: brass, vinyl, Bollywood posters and genuine "
          'antiques. Fridays and Sundays are the best days to dig.',
      imageUrl: 'https://picsum.photos/seed/localiq-chor-bazaar/640/480',
      tags: <String>['antiques', 'vintage', 'bargain', 'photography'],
      accessibilityFlags: <String>[],
      indoorOutdoor: IndoorOutdoor.mixed,
      localGemScore: 0.9,
    ),
    Place(
      id: '14',
      name: 'Carter Road Promenade',
      category: PlaceCategory.outdoor,
      area: 'Bandra',
      lat: 19.062,
      lng: 72.8265,
      avgCost: 150,
      durationMin: 75,
      openTime: '06:00',
      closeTime: '20:00',
      rating: 4.5,
      reviewCount: 1900,
      description:
          'Bandra\'s evening living room: a sea-facing promenade, skate park, '
          'dog walkers and musicians as the sun drops behind Worli.',
      imageUrl: 'https://picsum.photos/seed/localiq-carter-road/640/480',
      tags: <String>['sunset', 'sea-face', 'walking', 'free'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.87,
    ),
    Place(
      id: '15',
      name: 'Bandra Nightlife Crawl',
      category: PlaceCategory.nightlife,
      area: 'Bandra',
      lat: 19.0596,
      lng: 72.8285,
      avgCost: 900,
      durationMin: 180,
      openTime: '18:00',
      closeTime: '01:00',
      rating: 4.3,
      reviewCount: 2000,
      description:
          'Chapel Road bars to the Bandstand sea face: live gigs, craft beer '
          'and a midnight sea breeze, all within a walkable loop.',
      imageUrl: 'https://picsum.photos/seed/localiq-nightlife/640/480',
      tags: <String>['bars', 'live-music', 'friends', 'late-night'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.mixed,
      localGemScore: 0.85,
    ),
    Place(
      id: '16',
      name: 'CSMT Heritage Walk',
      category: PlaceCategory.culture,
      area: 'Fort',
      lat: 18.9398,
      lng: 72.8355,
      avgCost: 150,
      durationMin: 120,
      openTime: '08:00',
      closeTime: '18:00',
      rating: 4.6,
      reviewCount: 2400,
      description:
          'A UNESCO Victorian Gothic terminus, plus Flora Fountain and the Fort '
          'lanes behind it. Best with a guide who points out the gargoyles.',
      imageUrl: 'https://picsum.photos/seed/localiq-csmt/640/480',
      tags: <String>['heritage', 'unesco', 'walking', 'architecture'],
      accessibilityFlags: <String>['step-free'],
      indoorOutdoor: IndoorOutdoor.outdoor,
      localGemScore: 0.85,
    ),
  ];

  static Place? byId(String? id) {
    if (id == null) return null;
    for (final Place place in all) {
      if (place.id == id) return place;
    }
    return null;
  }

  static List<Place> byCategory(PlaceCategory category) {
    return all.where((Place p) => p.category == category).toList();
  }
}
