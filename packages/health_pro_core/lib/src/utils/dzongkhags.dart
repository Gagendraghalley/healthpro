import '../venues/venue_map.dart' show distanceKm;

/// Bhutan's 20 dzongkhags, for addresses and for filtering venues.
const dzongkhags = [
  'Bumthang',
  'Chhukha',
  'Dagana',
  'Gasa',
  'Haa',
  'Lhuentse',
  'Mongar',
  'Paro',
  'Pemagatshel',
  'Punakha',
  'Samdrup Jongkhar',
  'Samtse',
  'Sarpang',
  'Thimphu',
  'Trashigang',
  'Trashiyangtse',
  'Trongsa',
  'Tsirang',
  'Wangdue Phodrang',
  'Zhemgang',
];

/// Each dzongkhag's main towns (its seat, and any larger town), where most
/// of its people are: latitude and longitude, near enough to tell which
/// dzongkhag a phone is in ([dzongkhagAt]).
const dzongkhagTowns = <(String, double, double)>[
  ('Bumthang', 27.549, 90.752), // Jakar
  ('Chhukha', 27.100, 89.534), // Tsimasham
  ('Chhukha', 26.852, 89.388), // Phuentsholing
  ('Chhukha', 26.922, 89.523), // Gedu
  ('Dagana', 27.067, 89.876),
  ('Gasa', 27.907, 89.727),
  ('Haa', 27.367, 89.281),
  ('Lhuentse', 27.667, 91.184),
  ('Mongar', 27.275, 91.240),
  ('Paro', 27.431, 89.413),
  ('Pemagatshel', 27.038, 91.403),
  ('Punakha', 27.567, 89.864), // Khuruthang
  ('Samdrup Jongkhar', 26.800, 91.505),
  ('Samtse', 26.899, 89.099),
  ('Sarpang', 26.864, 90.267),
  ('Sarpang', 26.870, 90.486), // Gelephu
  ('Thimphu', 27.473, 89.639),
  ('Trashigang', 27.333, 91.553),
  ('Trashiyangtse', 27.611, 91.498),
  ('Trongsa', 27.500, 90.507),
  ('Tsirang', 27.008, 90.123), // Damphu
  ('Wangdue Phodrang', 27.486, 89.899), // Bajo
  ('Zhemgang', 27.217, 90.658),
];

/// The dzongkhag a place ([latitude], [longitude]) is in: that of the
/// nearest main town, worked out on the phone (where they are goes nowhere).
/// Null more than 60 km from every one: outside Bhutan.
String? dzongkhagAt(double latitude, double longitude) {
  String? nearest;
  var best = 60.0;
  for (final (name, lat, lng) in dzongkhagTowns) {
    final km = distanceKm(latitude, longitude, lat, lng);
    if (km < best) {
      best = km;
      nearest = name;
    }
  }
  return nearest;
}
