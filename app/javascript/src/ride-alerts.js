// "Alert me about this route": saves the route from the search form so the platform can tell the
// person when a matching trip is posted.
$(document).on('click', '#create-alert-button', function () {
  const $button = $(this)
  const $status = $('#alert-status')
  const value = name => $(`#itineraries_search_${name}`).val()
  const payload = {
    from: value('from'),
    to: value('to'),
    start_location_lng: value('start_location_lng'),
    start_location_lat: value('start_location_lat'),
    end_location_lng: value('end_location_lng'),
    end_location_lat: value('end_location_lat')
  }

  if (!payload.start_location_lat || !payload.end_location_lat) {
    $status.text($button.data('missing') || 'Search for a route first.')
    return
  }

  $button.prop('disabled', true)
  $.ajax({
    url: $button.data('url'),
    method: 'POST',
    dataType: 'json',
    headers: { 'X-CSRF-Token': $('meta[name=csrf-token]').attr('content') },
    data: { ride_alert: payload }
  }).done(response => $status.text(response.message))
    .fail(xhr => $status.text((xhr.responseJSON && xhr.responseJSON.message) || 'Could not save the alert.'))
    .always(() => $button.prop('disabled', false))
})
