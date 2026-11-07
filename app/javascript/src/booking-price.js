// Updates the fare, service fee and total as a passenger changes the number of seats.
const money = (amount, symbol) => `${Number(amount).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${symbol}`

$(document).on('change input', '[data-price-calc] select, [data-price-calc] input[data-price-dates]', function () {
  const $box = $(this).closest('[data-price-calc]')
  const price = Number($box.data('price'))
  const percent = Number($box.data('feePercent'))
  const chargedToPassenger = $box.data('chargedTo') === 'passenger'
  const symbol = $box.data('symbol')
  const seats = Number($box.find('select').val()) || 1
  const dates = $box.find('input[data-price-dates]').length ? Math.max($box.find('input[data-price-dates]:checked').length, 1) : 1

  const fare = price * seats * dates
  const fee = Math.round(fare * percent) / 100
  const total = chargedToPassenger ? fare + fee : fare

  $box.find('[data-fare]').text(money(fare, symbol))
  $box.find('[data-fee]').text(money(fee, symbol))
  $box.find('[data-total]').text(money(total, symbol))
  $box.find('.breakdown td:first-child').first().text(`${seats} × ${dates > 1 ? `${dates} × ` : ''}${money(price, symbol)}`)
})
