/// Shared profile option lists used by both the onboarding wizard and
/// the edit-profile screen. Single source of truth — import this file
/// instead of defining duplicate lists.
library;

/// HIV status options.
const kHivStatusOptions = <String>[
  'Unknown',
  'Negative',
  'Positive',
  'Prefer not to say',
];

/// Gender identity options.
const kGenderOptions = <String>[
  'Man',
  'Woman',
  'Non-binary',
  'Transgender',
  'Other',
];

/// Tribe / community labels.
const kTribeOptions = <String>[
  'Bear',
  'Twink',
  'Jock',
  'Otter',
  'Daddy',
  'Geek',
  'Leather',
  'Pup',
  'Muscle',
  'Chub',
  'Trans',
  'Queer',
  'Drag',
  'Furry',
  'Military',
  'Poz',
  'Clean',
  'Discreet',
];

/// Relationship status options.
const kRelationshipStatusOptions = <String>[
  'Single',
  'Taken',
  'Open',
  'Married',
  'Prefer not to say',
];

/// Sexual position preference options.
const kPositionOptions = <String>[
  'Top',
  'Bottom',
  'Versatile',
  'Side',
  'Oral',
  'Other',
];

/// "Looking for" reasons to connect.
const kLookingForOptions = <String>[
  'Chat',
  'Friends',
  'Dates',
  'Relationship',
  'Networking',
  'Right Now',
];

/// Ethnicity / heritage options.
const kEthnicityOptions = <String>[
  'Latino',
  'White',
  'Black',
  'Asian',
  'Middle Eastern',
  'Indigenous',
  'South Asian',
  'Mixed',
  'Other',
];

/// Pronouns options.
const kPronounsOptions = <String>[
  'he/him',
  'she/her',
  'they/them',
  'he/they',
  'she/they',
  'Other',
];

/// Body type options.
const kBodyTypeOptions = <String>[
  'Slim',
  'Average',
  'Athletic',
  'Muscular',
  'Curvy',
  'Stocky',
  'Large',
];

/// Meeting place options.
const kMeetAtOptions = <String>[
  'Bar',
  'Cafe',
  'Gym',
  'Park',
  'Beach',
  'Club',
  'Sauna',
  'Home',
  'Other',
];

/// Interest / tag options.
const kTagOptions = <String>[
  'Fitness',
  'Music',
  'Travel',
  'Food',
  'Art',
  'Movies',
  'Reading',
  'Gaming',
  'Outdoors',
  'Tech',
  'Cooking',
  'Photography',
  'Dancing',
  'Yoga',
  'Pets',
  'Fashion',
];

/// User role options.
const kRoleOptions = <String>['user', 'verificado', 'premium'];
