// lib/widgets/place_categories.dart
//
// Taxonomía única de categorías de lugar (itinerary_places.category).
// Fuente compartida de emoji/icono/color para que la misma parada se
// vea igual la añadas desde el plan privado del viaje (TripDetailScreen)
// o la veas luego en el itinerario publicado (ItineraryDetailScreen).

import 'package:flutter/material.dart';
import 'common_widgets.dart';

class PlaceCategory {
  final String label;
  final String emoji;
  final IconData icon;
  final Color color;
  const PlaceCategory({
    required this.label,
    required this.emoji,
    required this.icon,
    required this.color,
  });
}

const List<PlaceCategory> kPlaceCategories = [
  PlaceCategory(label: 'Restaurants', emoji: '🍽️', icon: Icons.restaurant, color: Color(0xFFFF7B54)),
  PlaceCategory(label: 'Activities',  emoji: '🎯', icon: Icons.local_activity_outlined, color: kPrimary),
  PlaceCategory(label: 'Museums',     emoji: '🏛️', icon: Icons.museum_outlined, color: Color(0xFF7C3AED)),
  PlaceCategory(label: 'Nature',      emoji: '🌿', icon: Icons.park_outlined, color: Color(0xFF10B981)),
  PlaceCategory(label: 'Shopping',    emoji: '🛍️', icon: Icons.shopping_bag_outlined, color: Color(0xFFEC4899)),
  PlaceCategory(label: 'Nightlife',   emoji: '🌙', icon: Icons.nightlife_outlined, color: Color(0xFF334155)),
  PlaceCategory(label: 'Hotel',       emoji: '🏨', icon: Icons.house_rounded, color: kTeal),
];

/// Resuelve una categoría guardada a su definición visual; si no se
/// reconoce (dato legado u otra fuente), cae en "Activities".
PlaceCategory placeCategory(String label) => kPlaceCategories.firstWhere(
      (c) => c.label == label,
      orElse: () => kPlaceCategories[1],
    );
