// Updates the fare, service fee and total as a passenger changes the number of seats.
const money = (amount, symbol) => `${Number(amount).toLocaleString('en-US', { maximumFractionDigits: 2 })} ${symbol}`

$(document).on('change input', '[data-price-calc] select', function () {
  const $box = $(this).closest('[data-price-calc]')
  const price = Number($box.data('price'))
  const percent = Number($box.data('feePercent'))
  const chargedToPassenger = $box.data('chargedTo') === 'passenger'
  const symbol = $box.data('symbol')
  const seats = Number(this.value) || 1

  const fare = price * seats
  const fee = Math.round(fare * percent) / 100
  const total = chargedToPassenger ? fare + fee : fare

  $box.find('[data-fare]').text(money(fare, symbol))
  $box.find('[data-fee]').text(money(fee, symbol))
  $box.find('[data-total]').text(money(total, symbol))
  $box.find('.breakdown td:first-child').first().text(function (_, text) {
    return text.replace(/^\d+/, seats)
  })
})
