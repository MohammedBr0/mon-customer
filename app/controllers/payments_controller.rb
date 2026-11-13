# frozen_string_literal: true

# The page Chapa sends the browser to after a payment. It only tells the person to go back to the app.
class PaymentsController < ActionController::Base # rubocop:disable Rails/ApplicationController
  def done
    render html: <<~HTML.html_safe, layout: false # rubocop:disable Rails/OutputSafety
      <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
      <title>#{ERB::Util.html_escape(APP_CONFIG.app_name)}</title>
      <style>body{font-family:system-ui,sans-serif;margin:0;min-height:100vh;display:grid;place-items:center;background:#1a56db;color:#fff;text-align:center;padding:24px}
      h1{font-size:1.6rem;margin:0 0 8px}p{margin:0;font-size:1.05rem}</style></head>
      <body><div><h1>#{ERB::Util.html_escape(I18n.t('wallet.done_title'))}</h1><p>#{ERB::Util.html_escape(I18n.t('wallet.done_body', app: APP_CONFIG.app_name))}</p></div></body></html>
    HTML
  end
end
