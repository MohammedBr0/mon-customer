# frozen_string_literal: true

module NeonAuthOmniauthable
  extend ActiveSupport::Concern

  included do
    def update_info_from_auth_hash!(auth_hash)
      update(
        email:                   auth_hash.info.email,
        image:                   (image if image.to_s.start_with?('/avatars/')) || auth_hash.info.image,
        name:                    auth_hash.info.name,
        access_token:            auth_hash.credentials.token,
        access_token_expires_at: access_token_expiration_from(auth_hash.credentials)
      )
    end

    private

    # OpenID Connect providers return either an absolute timestamp or a lifetime in seconds.
    def access_token_expiration_from(credentials)
      if credentials.expires_at.present?
        Time.zone.at(credentials.expires_at.to_i)
      elsif credentials.expires_in.present?
        credentials.expires_in.to_i.seconds.from_now
      end
    end
  end
end
