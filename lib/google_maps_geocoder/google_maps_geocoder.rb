require 'active_support'
require 'logger'
require 'net/http'
require 'rack'

# A simple PORO wrapper for geocoding with Google Maps.
#
# @example
#   chez_barack = GoogleMapsGeocoder.new '1600 Pennsylvania Ave'
#   chez_barack.formatted_address
#     => "1600 Pennsylvania Avenue Northwest, President's Park,
#         Washington, DC 20500, USA"
class GoogleMapsGeocoder
  # A geocoding error returned by Google Maps.
  class GeocodingError < StandardError
    # Returns the complete JSON response from Google Maps as a Hash.
    #
    # @return [Hash] Google Maps' JSON response
    # @example
    #   {
    #     "results" => [],
    #     "status" => "ZERO_RESULTS"
    #   }
    attr_reader :json

    # Initialize a GeocodingError wrapping the JSON returned by Google Maps.
    #
    # @param json [Hash] Google Maps' JSON response
    # @return [GeocodingError] the geocoding error
    def initialize(json = {})
      @json = json
      super @json['status']
    end
  end

  GOOGLE_ADDRESS_SEGMENTS = %i[
    city country_long_name country_short_name county lat lng postal_code
    state_long_name state_short_name
  ].freeze
  GOOGLE_MAPS_API = 'https://maps.googleapis.com/maps/api/geocode/json'.freeze

  ALL_ADDRESS_SEGMENTS = (
    GOOGLE_ADDRESS_SEGMENTS + %i[formatted_address formatted_street_address]
  ).freeze

  # Returns the complete formatted address with standardized abbreviations.
  #
  # @return [String] the complete formatted address
  # @example
  #   chez_barack.formatted_address
  #     => "1600 Pennsylvania Avenue Northwest, President's Park,
  #         Washington, DC 20500, USA"
  attr_reader :formatted_address

  # Returns the formatted street address with standardized abbreviations.
  #
  # @return [String] the formatted street address
  # @example
  #   chez_barack.formatted_street_address
  #     => "1600 Pennsylvania Avenue"
  attr_reader :formatted_street_address
  # Self-explanatory
  attr_reader(*GOOGLE_ADDRESS_SEGMENTS)

  # Geocodes the specified address and wraps the results in a GoogleMapsGeocoder
  # object.
  #
  # @param address [String] a geocodable address
  # @return [GoogleMapsGeocoder] the Google Maps result for the specified
  #   address
  # @example
  #   chez_barack = GoogleMapsGeocoder.new '1600 Pennsylvania Ave'
  def initialize(address)
    @json = address.is_a?(String) ? google_maps_response(address) : address
    raise GeocodingError, @json if @json.blank? || @json['status'] != 'OK'
    set_attributes_from_json
    logger.info('GoogleMapsGeocoder') do
      "Geocoded \"#{address}\" => \"#{formatted_address}\""
    end
  end

  # Returns true if the address Google returns is an exact match.
  #
  # @return [boolean] whether the Google Maps result is an exact match
  # @example
  #   chez_barack.exact_match?
  #     => true
  def exact_match?
    !partial_match?
  end

  # Returns true if the address Google returns isn't an exact match.
  #
  # @return [boolean] whether the Google Maps result is a partial match
  # @example
  #   GoogleMapsGeocoder.new('1600 Pennsylvania Washington').partial_match?
  #     => true
  def partial_match?
    @json['results'][0]['partial_match'] == true
  end

  private

  def google_maps_api_key
    @google_maps_api_key ||= "&key=#{ENV['GOOGLE_MAPS_API_KEY']}" if
      ENV['GOOGLE_MAPS_API_KEY']
  end

  def google_maps_request(query)
    "#{GOOGLE_MAPS_API}?address=#{Rack::Utils.escape query}&sensor=false"\
    "#{google_maps_api_key}"
  end

  def google_maps_response(address)
    uri = URI.parse google_maps_request(address)
    response = http(uri).request(Net::HTTP::Get.new(uri.request_uri))
    ActiveSupport::JSON.decode response.body
  end

  def http(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http
  end

  def logger
    @logger ||= Logger.new STDERR
  end

  def parse_address_component_type(type, name = 'long_name')
    address_component = @json['results'][0]['address_components'].detect do |ac|
      ac['types'] && ac['types'].include?(type)
    end
    address_component && address_component[name]
  end

  def parse_city
    parse_address_component_type('sublocality') ||
      parse_address_component_type('locality')
  end

  def parse_country_long_name
    parse_address_component_type('country')
  end

  def parse_country_short_name
    parse_address_component_type('country', 'short_name')
  end

  def parse_county
    parse_address_component_type('administrative_area_level_2')
  end

  def parse_formatted_address
    @json['results'][0]['formatted_address']
  end

  def parse_formatted_street_address
    "#{parse_address_component_type('street_number')} "\
    "#{parse_address_component_type('route')}"
  end

  def parse_lat
    @json['results'][0]['geometry']['location']['lat']
  end

  def parse_lng
    @json['results'][0]['geometry']['location']['lng']
  end

  def parse_postal_code
    parse_address_component_type('postal_code')
  end

  def parse_state_long_name
    parse_address_component_type('administrative_area_level_1')
  end

  def parse_state_short_name
    parse_address_component_type('administrative_area_level_1', 'short_name')
  end

  def set_attributes_from_json
    ALL_ADDRESS_SEGMENTS.each do |segment|
      instance_variable_set :"@#{segment}", send("parse_#{segment}")
    end
  end
end
