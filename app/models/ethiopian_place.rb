# frozen_string_literal: true

# Towns and cities riders can pick in the mobile app, with coordinates. Search and trip creation work
# from coordinates, so the app does not need a maps service to offer a route.
class EthiopianPlace
  Place = Struct.new(:key, :name, :name_am, :lat, :lng, :city, keyword_init: true) do
    def label(locale = I18n.locale)
      locale.to_s.start_with?('am') && name_am.present? ? name_am : name
    end

    def as_json(*)
      { key:, name:, name_am:, lat:, lng:, city: }.compact
    end
  end

  ALL = [
    ['Addis Ababa', 'አዲስ አበባ', 9.0192, 38.7525], ['Adama', 'አዳማ', 8.54, 39.27], ['Hawassa', 'ሀዋሳ', 7.0621, 38.4763],
    ['Bahir Dar', 'ባሕር ዳር', 11.5936, 37.3908], ['Dire Dawa', 'ድሬዳዋ', 9.5931, 41.8661], ['Mekelle', 'መቀሌ', 13.4967, 39.4753],
    ['Gondar', 'ጎንደር', 12.603, 37.4521], ['Jimma', 'ጅማ', 7.6781, 36.8344], ['Dessie', 'ደሴ', 11.1333, 39.6333],
    ['Kombolcha', 'ኮምቦልቻ', 11.0833, 39.7333], ['Jijiga', 'ጅጅጋ', 9.35, 42.8], ['Harar', 'ሐረር', 9.3126, 42.118],
    ['Arba Minch', 'አርባ ምንጭ', 6.0333, 37.55], ['Debre Markos', 'ደብረ ማርቆስ', 10.3333, 37.7167], ['Debre Birhan', 'ደብረ ብርሃን', 9.6804, 39.5306],
    ['Shashemene', 'ሻሸመኔ', 7.2, 38.6], ['Nekemte', 'ነቀምቴ', 9.0833, 36.55], ['Bishoftu', 'ቢሾፍቱ', 8.75, 38.9833],
    ['Mojo', 'ሞጆ', 8.5833, 39.1167], ['Woldiya', 'ወልዲያ', 11.8333, 39.6], ['Axum', 'አክሱም', 14.1211, 38.7247],
    ['Adigrat', 'አዲግራት', 14.2766, 39.4611], ['Shire', 'ሽሬ', 14.1, 38.2833], ['Wolaita Sodo', 'ሶዶ', 6.85, 37.75],
    ['Hosaena', 'ሆሳዕና', 7.55, 37.85], ['Dilla', 'ዲላ', 6.4, 38.3167], ['Asella', 'አሰላ', 7.95, 39.1333],
    ['Ambo', 'አምቦ', 8.9833, 37.85], ['Woliso', 'ወሊሶ', 8.5333, 37.9833], ['Welkite', 'ወልቂጤ', 8.2833, 37.7833],
    ['Butajira', 'ቡታጅራ', 8.1167, 38.3667], ['Metu', 'መቱ', 8.3, 35.5833], ['Gambela', 'ጋምቤላ', 8.25, 34.5833],
    ['Semera', 'ሰመራ', 11.79, 41.01], ['Assosa', 'አሶሳ', 10.0667, 34.5333], ['Lalibela', 'ላሊበላ', 12.0319, 39.0475],
    ['Debre Tabor', 'ደብረ ታቦር', 11.85, 38.0167], ['Goba', 'ጎባ', 7.0167, 39.9833], ['Negele Borana', 'ነገሌ', 5.3333, 39.5833],
    ['Yabelo', 'ያቤሎ', 4.8833, 38.0833], ['Moyale', 'ሞያሌ', 3.5167, 39.05]
  ].map { |name, am, lat, lng| Place.new(key: name.parameterize, name:, name_am: am, lat:, lng:) }.freeze

  # Neighbourhoods inside a city, for commutes that never leave town. Coordinates are approximate centres
  # (good to within about a kilometre), which is what the city search radius assumes.
  AREAS = {
    'addis-ababa' => [
      ['Bole', 'ቦሌ', 8.9967, 38.7867], ['Bole Medhanealem', 'ቦሌ መድኃኔዓለም', 8.9937, 38.7745], ['Piassa', 'ፒያሳ', 9.0350, 38.7467],
      ['Mexico', 'ሜክሲኮ', 9.0100, 38.7400], ['Megenagna', 'መገናኛ', 9.0200, 38.8000], ['CMC', 'ሲኤምሲ', 9.0300, 38.8350],
      ['Sarbet', 'ሳርቤት', 8.9880, 38.7270], ['Kazanchis', 'ካዛንቺስ', 9.0150, 38.7650], ['Merkato', 'መርካቶ', 9.0350, 38.7350],
      ['Lideta', 'ልደታ', 9.0120, 38.7300], ['Gerji', 'ገርጂ', 9.0050, 38.8250], ['Ayat', 'አያት', 9.0220, 38.8700],
      ['Summit', 'ሰሚት', 9.0000, 38.8600], ['4 Kilo', 'አራት ኪሎ', 9.0350, 38.7620], ['6 Kilo', 'ስድስት ኪሎ', 9.0450, 38.7600],
      ['Lebu', 'ለቡ', 8.9550, 38.7150], ['Saris', 'ሳሪስ', 8.9650, 38.7600], ['Kality', 'ቃሊቲ', 8.9100, 38.7800],
      ['Jemo', 'ጀሞ', 8.9700, 38.7050], ['Gotera', 'ጎተራ', 8.9900, 38.7600], ['Old Airport', 'አሮጌው ኤርፖርት', 8.9990, 38.7200],
      ['Stadium', 'ስታዲየም', 9.0120, 38.7580], ['Mekanisa', 'መካኒሳ', 8.9830, 38.7350], ['Shiro Meda', 'ሽሮ ሜዳ', 9.0560, 38.7500]
    ]
  }.freeze

  AREA_PLACES = AREAS.flat_map do |city_key, areas|
    areas.map { |name, am, lat, lng| Place.new(key: "#{city_key}:#{name.parameterize}", name:, name_am: am, lat:, lng:, city: city_key) }
  end.freeze

  def self.all
    ALL
  end

  # Cities that have neighbourhoods to choose from.
  def self.cities_with_areas
    ALL.select { |place| AREAS.key?(place.key) }
  end

  def self.areas(city_key)
    AREA_PLACES.select { |place| place.city == city_key.to_s }
  end

  # Finds a town, or a neighbourhood by its "city:area" key.
  def self.find(key)
    ALL.find { |place| place.key == key.to_s } || AREA_PLACES.find { |place| place.key == key.to_s }
  end

  # Nearest known place to a point (used to label a position in a few words).
  def self.nearest(lat, lng)
    ALL.min_by { |place| ((place.lat - lat.to_f)**2) + ((place.lng - lng.to_f)**2) }
  end
end
