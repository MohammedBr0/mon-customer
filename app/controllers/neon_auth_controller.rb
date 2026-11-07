# frozen_string_literal: true

# Login and consent pages for Neon Auth's OAuth provider. Neon Auth redirects the
# browser here (with a signed `oauth_query`) and the pages complete the flow by
# calling Neon Auth directly from the browser.
class NeonAuthController < ApplicationController
  skip_before_action :authenticate_user!

  layout 'neon_auth'

  def login; end

  def consent; end
end
