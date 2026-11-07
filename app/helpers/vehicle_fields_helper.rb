# frozen_string_literal: true

# Renders one admin-configured vehicle question as a form control.
module VehicleFieldsHelper
  def vehicle_field_input(user, field)
    name = "user[vehicle_data][#{field.key}]"
    id = "user_vehicle_data_#{field.key}"
    value = user.vehicle_value(field.key)

    case field.field_type
    when 'select'
      select_tag name, options_for_select(field.options_list, value), include_blank: true, id: id, class: 'form-select'
    when 'number'
      number_field_tag name, value, id: id, min: field.min_value, max: field.max_value, inputmode: 'numeric', class: 'form-control'
    when 'boolean'
      tag.div(class: 'form-check') do
        hidden_field_tag(name, '0', id: nil) +
          check_box_tag(name, '1', value == true, id: id, class: 'form-check-input') +
          label_tag(id, field.label_for, class: 'form-check-label')
      end
    else
      text_field_tag name, value, id: id, maxlength: VehicleField::MAX_TEXT_LENGTH, class: 'form-control'
    end
  end

  def vehicle_visibility_hint(field)
    t("vehicle.visibility.#{field.visibility}")
  end
end
