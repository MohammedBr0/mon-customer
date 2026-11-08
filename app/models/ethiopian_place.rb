# frozen_string_literal: true

# Towns and cities riders can pick in the mobile app, with coordinates. Search and trip creation work
# from coordinates, so the app does not need a maps service to offer a route.
class EthiopianPlace
  Place = Struct.new(:key, :name, :name_am, :lat, :lng, keyword_init: true) do
    def label(locale = I18n.locale)
      locale.to_s.start_with?('am') && name_am.present? ? name_am : name
    end

    def as_json(*)
      { key:, name:, name_am:, lat:, lng: }
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

  def self.all
    ALL
  end

  def self.find(key)
    ALL.find { |place| place.key == key.to_s }
  end

  # Nearest known place to a point (used to label a position in a few words).
  def self.nearest(lat, lng)
    ALL.min_by { |place| ((place.lat - lat.to_f)**2) + ((place.lng - lng.to_f)**2) }
  end
end
