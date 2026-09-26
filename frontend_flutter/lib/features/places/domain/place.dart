import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/json_map_x.dart';
import '../../context/domain/context_models.dart';

/// A physical venue. An [Experience] is an activity *at* a place, so one place
/// can yield several rankable experiences.
@immutable
class Place {
  const Place({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.area,
    required this.centre,
    required this.heroImageUrl,
    required this.imageUrls,
    required this.openingHours,
    required this.accessibility,
    required this.rating,
    required this.reviewCount,
    required this.priceLevel,
    required this.typicalSpend,
    required this.crowdLevel,
    required this.indoor,
    required this.localFavourite,
    required this.bookingRequired,
    this.phone,
    this.website,
    this.summary,
  });

  final String id;
  final String name;
  final ExperienceCategory category;
  final String address;
  final String area;
  final GeoPoint centre;
  final String heroImageUrl;
  final List<String> imageUrls;
  final OpeningHours openingHours;
  final AccessibilityProfile accessibility;
  final double rating;
  final int reviewCount;

  /// 0–4, aligned with Google Places price levels.
  final int priceLevel;

  final int typicalSpend;
  final CrowdLevel crowdLevel;
  final bool indoor;
  final bool localFavourite;
  final bool bookingRequired;
  final String? phone;
  final String? website;
  final String? summary;

  String get priceLabel => typicalSpend == 0 ? 'Free' : '₹$typicalSpend';

  factory Place.fromJson(Map<String, dynamic> json) {
    final images = json.stringList('imageUrls');
    return Place(
      id: json.string('id') ?? '',
      name: json.string('name') ?? 'Unnamed place',
      category: ExperienceCategory.parse(json.string('category')),
      address: json.string('address') ?? '',
      area: json.string('area') ?? '',
      centre: GeoPoint.fromJson(json.mapOrEmpty('centre')),
      heroImageUrl: json.stringOrNull('heroImageUrl') ?? images.firstOrNull ?? '',
      imageUrls: images,
      openingHours: OpeningHours.fromJson(json.mapOrEmpty('openingHours')),
      accessibility: AccessibilityProfile.fromJson(
        json.mapOrEmpty('accessibility'),
      ),
      rating: json.doubleValue('rating', fallback: 4.0),
      reviewCount: json.intValue('reviewCount'),
      priceLevel: json.intValue('priceLevel', fallback: 1),
      typicalSpend: json.intValue('typicalSpend'),
      crowdLevel: CrowdLevelX.parse(json.string('crowdLevel')),
      indoor: json.boolValue('indoor'),
      localFavourite: json.boolValue('localFavourite'),
      bookingRequired: json.boolValue('bookingRequired'),
      phone: json.stringOrNull('phone'),
      website: json.stringOrNull('website'),
      summary: json.stringOrNull('summary'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'address': address,
        'area': area,
        'centre': centre.toJson(),
        'hero_image_url': heroImageUrl,
        'image_urls': imageUrls,
        'opening_hours': openingHours.toJson(),
        'accessibility': accessibility.toJson(),
        'rating': rating,
        'review_count': reviewCount,
        'price_level': priceLevel,
        'typical_spend': typicalSpend,
        'crowd_level': crowdLevel.name,
        'indoor': indoor,
        'local_favourite': localFavourite,
        'booking_required': bookingRequired,
        'phone': phone,
        'website': website,
        'summary': summary,
      };
}

enum CrowdLevel { quiet, moderate, busy, veryBusy }

extension CrowdLevelX on CrowdLevel {
  String get label => switch (this) {
        CrowdLevel.quiet => 'Quiet',
        CrowdLevel.moderate => 'Moderate',
        CrowdLevel.busy => 'Busy',
        CrowdLevel.veryBusy => 'Very busy',
      };

  static CrowdLevel parse(String? value) {
    if (value == null) return CrowdLevel.moderate;
    final needle = value.toLowerCase().replaceAll('_', '');
    return CrowdLevel.values.firstWhere(
      (c) => c.name.toLowerCase() == needle,
      orElse: () => CrowdLevel.moderate,
    );
  }
}

/// How weather affects a place. Drives the feasibility engine directly.
enum WeatherSuitability {
  indoorOnly('Indoor only'),
  sheltered('Sheltered'),
  weatherSensitive('Weather sensitive'),
  allWeather('All weather');

  const WeatherSuitability(this.label);

  final String label;

  bool get toleratesRain => this == indoorOnly || this == sheltered || this == allWeather;

  static WeatherSuitability parse(String? value) {
    if (value == null) return WeatherSuitability.allWeather;
    final needle = value.toLowerCase().replaceAll('_', '');
    return WeatherSuitability.values.firstWhere(
      (w) => w.name.toLowerCase() == needle,
      orElse: () => WeatherSuitability.allWeather,
    );
  }
}

/// A rankable, time-bounded activity at a [Place].
///
/// This is the unit the recommendation engine scores. It carries both the
/// intrinsic facts (duration, price, opening hours) and the derived,
/// context-specific fields (travel time, feasibility) that a given
/// [DiscoveryContext] produces.
@immutable
class Experience {
  const Experience({
    required this.id,
    required this.placeId,
    required this.title,
    required this.tagline,
    required this.description,
    required this.category,
    required this.secondaryCategory,
    required this.imageUrl,
    required this.activityMinutes,
    required this.typicalSpend,
    required this.weatherSuitability,
    required this.bookingNote,
    required this.localScore,
    required this.touristScore,
    required this.highlights,
    required this.practicalTip,
    this.minimumMinutes = 30,
    this.flexibleTiming = true,
  });

  final String id;
  final String placeId;
  final String title;
  final String tagline;
  final String description;
  final ExperienceCategory category;
  final String secondaryCategory;
  final String imageUrl;

  /// Time actually spent on the experience.
  final int activityMinutes;

  /// Shortest worthwhile visit.
  final int minimumMinutes;
  final bool flexibleTiming;
  final int typicalSpend;
  final WeatherSuitability weatherSuitability;
  final String bookingNote;

  /// 0–100, how strongly locals rate this.
  final double localScore;

  /// 0–100, how tourist-facing the experience is.
  final double touristScore;

  final List<String> highlights;
  final String? practicalTip;

  bool get toleratesRain => weatherSuitability.toleratesRain;

  String get priceLabel => typicalSpend == 0 ? 'Free' : '₹$typicalSpend';

  /// A 0–1 "is this worth it" score, independent of any user context.
  double intrinsicValue() {
    final base = 0.55 + (typicalSpend == 0 ? 0.12 : 0.0);
    final timeValue = (60 / activityMinutes.clamp(20, 240));
    return (base * timeValue * 100).clamp(0, 100);
  }

  factory Experience.fromJson(Map<String, dynamic> json) {
    return Experience(
      id: json.string('id') ?? '',
      placeId: json.string('placeId') ?? '',
      title: json.string('title') ?? 'Experience',
      tagline: json.stringOrNull('tagline') ?? '',
      description: json.string('description') ?? '',
      category: ExperienceCategory.parse(json.string('category')),
      secondaryCategory: json.string('secondaryCategory') ?? '',
      imageUrl: json.stringOrNull('imageUrl') ?? '',
      activityMinutes: json.intValue('activityMinutes', fallback: 60),
      minimumMinutes: json.intValue('minimumMinutes', fallback: 30),
      flexibleTiming: json.boolValue('flexibleTiming', fallback: true),
      typicalSpend: json.intValue('typicalSpend'),
      weatherSuitability: WeatherSuitability.parse(
        json.string('weatherSuitability'),
      ),
      bookingNote: json.string('bookingNote') ?? 'Walk-in',
      localScore: json.doubleValue('localScore', fallback: 50),
      touristScore: json.doubleValue('touristScore', fallback: 50),
      highlights: json.stringList('highlights'),
      practicalTip: json.stringOrNull('practicalTip'),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'place_id': placeId,
        'title': title,
        'tagline': tagline,
        'description': description,
        'category': category.name,
        'secondary_category': secondaryCategory,
        'image_url': imageUrl,
        'activity_minutes': activityMinutes,
        'minimum_minutes': minimumMinutes,
        'flexible_timing': flexibleTiming,
        'typical_spend': typicalSpend,
        'weather_suitability': weatherSuitability.name,
        'booking_note': bookingNote,
        'local_score': localScore,
        'tourist_score': touristScore,
        'highlights': highlights,
        'practical_tip': practicalTip,
      };
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Category colour used for pins, chips and image tinting.
Color categoryColor(ExperienceCategory category) {
  switch (category) {
    case ExperienceCategory.food:
      return const Color(0xFFD2691E);
    case ExperienceCategory.art:
      return AppColors.violet;
    case ExperienceCategory.history:
      return const Color(0xFF8B5E3C);
    case ExperienceCategory.culture:
      return AppColors.blue;
    case ExperienceCategory.nature:
      return AppColors.success;
    case ExperienceCategory.heritage:
      return const Color(0xFF0E5F7A);
    case ExperienceCategory.nightlife:
      return const Color(0xFF7B3FA0);
    case ExperienceCategory.shopping:
      return const Color(0xFFA8387A);
    case ExperienceCategory.wellness:
      return const Color(0xFF2C7A6B);
    case ExperienceCategory.adventure:
      return const Color(0xFFB4531F);
    case ExperienceCategory.localLife:
      return const Color(0xFF44506B);
  }
}
