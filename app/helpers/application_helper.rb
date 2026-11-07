# frozen_string_literal: true

module ApplicationHelper
  def google_maps_api_source
    if APP_CONFIG.google_maps_api_key
      "https://maps.googleapis.com/maps/api/js?libraries=geometry&callback=initMap&key=#{APP_CONFIG.google_maps_api_key}"
    else
      'https://maps.googleapis.com/maps/api/js?libraries=geometry&callback=initMap'
    end
  end

  def map_config_attributes
    {
      'data-map-center': APP_CONFIG.map.center,
      'data-map-zoom':   APP_CONFIG.map.zoom
    }
  end

  def platform_setting
    @platform_setting ||= PlatformSetting.current
  end

  # "1,250 Br", with cents only when there are some.
  def money(amount)
    value = amount.to_d
    number = number_with_precision(value, precision: value.frac.zero? ? 0 : 2, delimiter: ',')
    "#{number} #{platform_setting.currency_symbol}"
  end

  def body_classes
    classes = []
    classes << 'has-tabbar' if user_signed_in?
    classes << 'has-sticky-cta' if content_for?(:sticky_cta)
    classes << 'landing' if action_name == 'home' && !user_signed_in?
    classes.join(' ')
  end

  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def meta_title(options = {})
    title = content_for(:title) || options[:fallback]
    title << " | #{APP_CONFIG.app_name}" unless user_signed_in? || title.blank?
    title
  end

  def twitterized_type(type)
    case type
    when 'alert' then 'alert-warning'
    when 'error' then 'alert-danger'
    when 'notice' then 'alert-info'
    when 'success' then 'alert-success'
    else type
    end
  end

  def transparent_gif_image_data
    'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='
  end

  def options_for_array_collection(model, attr_name, *_args)
    "#{model}::#{attr_name.to_s.upcase}".safe_constantize.map { |e| [model.human_attribute_name("#{attr_name}_#{e}"), e] }
  end
end
