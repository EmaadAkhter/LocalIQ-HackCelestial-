import '../../../models/quest.dart';

const List<Quest> kLocalQuests = [
  Quest(
    id: 'q1',
    title: 'South Mumbai Art Deco & Heritage Circuit',
    description:
        'Discover the world’s second largest ensemble of Art Deco buildings, hidden colonial crests, and historic court verandas.',
    coverImageUrl: 'https://images.unsplash.com/photo-1570168007204-dfb528c6958f',
    totalMinutes: 135,
    estimatedCostInr: 250,
    difficulty: QuestDifficulty.easy,
    tags: ['Heritage', 'Architecture', 'Walking'],
    reward: QuestReward(
      xpPoints: 350,
      badgeId: 'deco_master',
      badgeLabel: 'Art Deco Master',
    ),
    stops: [
      QuestStop(
        stopNumber: 1,
        placeId: 'p1',
        placeName: 'Oval Maidan Deco Promenade',
        task: 'Find the nautical porthole balconies facing the cricket pitch.',
        activityMinutes: 30,
      ),
      QuestStop(
        stopNumber: 2,
        placeId: 'p2',
        placeName: 'Flora Fountain & Oriental Building',
        task: 'Spot the Roman goddess Flora carved in imported Portland stone.',
        activityMinutes: 25,
      ),
      QuestStop(
        stopNumber: 3,
        placeId: 'p3',
        placeName: 'Asiatic Society Library Steps',
        task: 'Climb the 30 neoclassical Doric steps and identify the vintage lamp posts.',
        activityMinutes: 35,
      ),
    ],
  ),
  Quest(
    id: 'q2',
    title: 'The Legendary Irani Chai & Maska Pilgrimage',
    description:
        'Step into century-old Persian cafes where time slowed down. Savor bun maska, berry pulao, and mawa cakes.',
    coverImageUrl: 'https://images.unsplash.com/photo-1561047029-3000c68339ca',
    totalMinutes: 105,
    estimatedCostInr: 450,
    difficulty: QuestDifficulty.easy,
    tags: ['Food Trail', 'Cafes', 'History'],
    reward: QuestReward(
      xpPoints: 280,
      badgeId: 'chai_connoisseur',
      badgeLabel: 'Irani Cafe Regular',
    ),
    stops: [
      QuestStop(
        stopNumber: 1,
        placeId: 'p4',
        placeName: 'Yazdani Bakery & Restaurant',
        task: 'Sample warm crusty brun maska fresh from the wood-fired German oven.',
        activityMinutes: 35,
      ),
      QuestStop(
        stopNumber: 2,
        placeId: 'p5',
        placeName: 'Cafe Excelsior',
        task: 'Try the classic caramel custard beside the vintage pendulum clock.',
        activityMinutes: 30,
      ),
      QuestStop(
        stopNumber: 3,
        placeId: 'p6',
        placeName: 'Britannia & Co.',
        task: 'Look for the framed portraits of Queen Victoria and taste the Berry Pulao.',
        activityMinutes: 40,
      ),
    ],
  ),
  Quest(
    id: 'q3',
    title: 'Marine Drive to Banganga Sacred Tanks',
    description:
        'Journey from the roaring Arabian Sea promenade to an ancient freshwater spring mentioned in the Ramayana.',
    coverImageUrl: 'https://images.unsplash.com/photo-1566552881560-0be862a7c445',
    totalMinutes: 160,
    estimatedCostInr: 150,
    difficulty: QuestDifficulty.moderate,
    tags: ['Culture', 'Seafront', 'Spiritual'],
    reward: QuestReward(
      xpPoints: 400,
      badgeId: 'tank_explorer',
      badgeLabel: 'Sacred Water Walker',
    ),
    stops: [
      QuestStop(
        stopNumber: 1,
        placeId: 'p7',
        placeName: 'Nariman Point Tetrapods',
        task: 'Watch the waves splash against the iconic concrete tetrapods.',
        activityMinutes: 40,
      ),
      QuestStop(
        stopNumber: 2,
        placeId: 'p8',
        placeName: 'Chowpatty Beach Promenade',
        task: 'Taste spicy kulfi or bhelpuri with coastal sunset views.',
        activityMinutes: 40,
      ),
      QuestStop(
        stopNumber: 3,
        placeId: 'p9',
        placeName: 'Banganga Tank Walk',
        task: 'Count the deepastambhas (lamp towers) enclosing the quiet waters.',
        activityMinutes: 50,
      ),
    ],
  ),
];
