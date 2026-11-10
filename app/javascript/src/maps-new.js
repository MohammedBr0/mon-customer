/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
/*
Itineraries
  people in the car: bool
  visibility: friends, friends of friends, public
  daily: think about it
*/

// From https://google-developers.appspot.com/maps/customize_ae458c7692ac994187feb6f58834b6af.frame

import i18n from './i18n'

window.icare = window.icare || {}
const {
  icare
} = window

// `route` is what /maps/route returns (Google Routes API through our server).
const setItinerary = function (route) {
  $('.itinerary-from-j').text(route.start_address)
  $('.itinerary-to-j').text(route.end_address)
  $('#distance').text(route.distance_text)
  $('#duration').text(route.duration_text)
  $('#copyrights').text('')
  $('#map-result-j').show()
  const routeKm = (Number)(route.distance_value / 1000)
  const routeGasoline = routeKm * (Number)($('#fuel-help').data('avg-consumption'))
  $('#fuel-help-text').text(i18n.t('javascript.fuel_help_text', { km: routeKm.toFixed(2), est: Math.ceil(routeGasoline), avg_consumption: $('#fuel-help').data('avg-consumption'), fuel_currency: $('html').data('fuelCurrency'), currency: $('html').data('currency') }))
  $('#fuel-help').show()
  // Suggest a price per seat that shares the fuel cost; the driver can change it.
  const seats = Number($('#itinerary_num_people').val()) || 3
  const $price = $('#itinerary_price_per_seat')
  if (!Number($price.val())) { $price.val(Math.max(5, Math.ceil(routeGasoline / (seats + 1) / 5) * 5)) }

  $('#remove-waypoints-link').hide()

  const data = {
    start_location: route.start_location,
    end_location: route.end_location,
    via_waypoints: [],
    overview_path: route.overview_path,
    overview_polyline: route.overview_polyline
  }

  window.icare.route = data
  return $('#itinerary_route').val(JSON.stringify(data))
}

const wizardPrevStep = function () {
  let step = (Number)($('div[data-step]:visible').data('step'))
  if (step <= 1) { return }

  return $(`#wizard-step-${step}-content`).fadeOut(function () {
    $('#wizard-next-step-button').prop('disabled', false).show()
    $('#new_itinerary_submit-j').prop('disabled', true).hide()

    $(`#wizard-step-${step}-title`).addClass('hidden-xs').removeClass('active')

    $(`#wizard-step-${step}-title`)
      .removeClass('hidden-xs').addClass('active')

    --step

    $(`#wizard-step-${step}-content`).fadeIn()

    if (step === 1) {
      $('#wizard-prev-step-button-j').prop('disabled', true).hide()
    }

    return $(window).scrollTop(`#wizard-step-${step}-title`)
  })
}

const wizardNextStep = function () {
  // Run validations
  if ($('#itinerary_route').val() === '') {
    $('#map-error-j').text(i18n.t('javascript.setup_route_first')).show()
    return false
  }

  let valid = true
  $('#new_itinerary [data-validate]:input:visible').each(function () {
    const {
      validators
    } = this.form.ClientSideValidations.settings
    if (!$(this).isValid(validators)) { valid = false }
  })
  if (!valid) { return false }

  let step = (Number)($('div[data-step]:visible').data('step'))
  const lastStep = (Number)($('div[data-step]').last().data('step'))

  if (step === lastStep) {
    return false
  }

  return $(`#wizard-step-${step}-content`).fadeOut(function () {
    $(`#wizard-step-${step}-title`)
      .removeClass('active').addClass('hidden-xs')

    ++step

    if (step === lastStep) {
      lastStepInit()
    }
    $(`#wizard-step-${step}-title`).removeClass('hidden-xs').addClass('active')

    $(`#wizard-step-${step}-content`).fadeIn(function () {
      $('#new_itinerary').enableClientSideValidations() // Enable validation for new fields
      return $(window).scrollTop(`#wizard-step-${step}-title`)
    })

    if (step > 1) {
      $('#wizard-prev-step-button-j').prop('disabled', false).show()
      if (step === lastStep) {
        $('#wizard-next-step-button').prop('disabled', true).hide()
        return $('#new_itinerary_submit-j').prop('disabled', false).show()
      }
    }
  })
}

const lastStepInit = function () {
  const {
    route
  } = window.icare
  const $itineraryPreviewImage = $('#itinerary-preview-image')
  if ($itineraryPreviewImage.hasClass('d-none')) { return }
  const googleMapsApiKey = $itineraryPreviewImage.data('googleMapsApiKey')
  return $itineraryPreviewImage.attr('src', `https://maps.googleapis.com/maps/api/staticmap?size=640x360&scale=2&markers=color:green|label:B|${route.end_location[1]},${route.end_location[0]}&markers=color:green|label:A|${route.start_location[1]},${route.start_location[0]}&path=enc:${route.overview_polyline}&key=${googleMapsApiKey}`)
}

// Draws the route from /maps/route on the map: the line, A and B markers, and zoomed to fit.
const drawRoute = function (state, route) {
  if (state.line) { state.line.setMap(null) }
  state.markers.forEach(marker => marker.setMap(null))
  const path = route.overview_path.map(point => ({ lat: point[1], lng: point[0] }))
  state.line = new google.maps.Polyline({ map: state.map, path, strokeColor: '#1a56db', strokeWeight: 5, strokeOpacity: 0.8 })
  state.markers = [
    new google.maps.Marker({ map: state.map, position: path[0], label: 'A' }),
    new google.maps.Marker({ map: state.map, position: path[path.length - 1], label: 'B' })
  ]
  const bounds = new google.maps.LatLngBounds()
  path.forEach(point => bounds.extend(point))
  state.map.fitBounds(bounds)
}

const calculateRoute = function (state) {
  if (($('#itinerary_start_address').val() === '') || ($('#itinerary_end_address').val() === '')) { return }
  $('#itineraries-spinner-j').show()
  $('#map-error-j').hide()
  $('#map-result-j').hide()
  $('#route-helper').hide()
  $('#copyrights').text('')
  $('#distance').text('')
  $('#duration').text('')
  $.getJSON('/maps/route', {
    origin: $('#itinerary_start_address').val(),
    destination: $('#itinerary_end_address').val(),
    avoid_highways: $('#itinerary_avoid_highways').prop('checked'),
    avoid_tolls: $('#itinerary_avoid_tolls').prop('checked')
  }).done(function (route) {
    $('#itineraries-spinner-j').hide()
    drawRoute(state, route)
    setItinerary(route)
    $('#new_itinerary_submit-j').prop('disabled', false)
  }).fail(function (xhr) {
    $('#itineraries-spinner-j').hide()
    const code = xhr.responseJSON && xhr.responseJSON.error
    let message
    switch (code) {
      case 'not_found':
        message = i18n.t('javascript.not_found')
        break
      case 'zero_results':
        message = i18n.t('javascript.zero_results')
        break
      default:
        message = i18n.t('javascript.an_error_occurred')
    }
    $('#map-error-j').text(message).show()
  })
}

const createRouteMapInit = function (id) {
  const state = { map: icare.initGoogleMaps(id), line: null, markers: [] }

  const $itineraryAddressInputs = $('#itinerary_start_address, #itinerary_end_address')

  // Get Route acts as submit
  $itineraryAddressInputs.on('keypress', function (e) {
    if (e && (e.keyCode === 13)) {
      e.preventDefault()
      return calculateRoute(state)
    }
  })

  $('#get-route').on('click', function () {
    let valid = true
    $('[data-validate]:input:visible').each(function () {
      const {
        validators
      } = this.form.ClientSideValidations.settings
      if (!$(this).isValid(validators)) { valid = false }
    })
    if (!valid) { return }
    return calculateRoute(state)
  })

  // Set route if it's already available
  return calculateRoute(state)
}

const initItineraryNew = function () {
  createRouteMapInit('#new-itinerary-map')
  $('#wizard-next-step-button').on('click', wizardNextStep)
  $('#wizard-prev-step-button-j').on('click', wizardPrevStep)
  return $('input[name="itinerary[daily]"]').change(function () {
    if (($(this).val() === 'true')) {
      return $('#single').fadeOut(() => $('#daily').fadeIn())
    } else {
      return $('#daily').fadeOut(() => $('#single').fadeIn())
    }
  })
}

$(document).on(window.initializeOnEvent, function () {
  if ((typeof google !== 'undefined' && google !== null) && ($('#new_itinerary')[0] != null)) {
    return initItineraryNew()
  }
})
