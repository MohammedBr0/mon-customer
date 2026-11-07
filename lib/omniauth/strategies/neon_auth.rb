# frozen_string_literal: true

require 'base64'
require 'json'
require 'openssl'
require 'omniauth_openid_connect'

module OmniAuth
  module Strategies
    # OpenID Connect strategy for Neon Auth (managed Better Auth).
    #
    # Neon Auth signs its ID tokens with EdDSA (Ed25519, JWK key type "OKP"). The json-jwt gem behind
    # omniauth_openid_connect cannot parse those keys ("Unknown key type"), so this strategy verifies
    # EdDSA signatures itself, using OpenSSL, against the provider's published JWKS. Issuer, audience,
    # expiry and nonce are then checked by the stock IdToken#verify! exactly as for any other provider.
    class NeonAuth < OpenIDConnect
      private

      def decode_id_token(id_token)
        header_b64, payload_b64, signature_b64 = id_token.to_s.split('.')
        raise_invalid_jwt!('Malformed ID token') if [header_b64, payload_b64, signature_b64].any?(&:blank?)

        header = JSON.parse(base64url_decode(header_b64))
        raise_invalid_jwt!("Unsupported ID token algorithm #{header['alg'].inspect}") unless header['alg'] == 'EdDSA'

        signing_input = "#{header_b64}.#{payload_b64}"
        signature     = base64url_decode(signature_b64)

        verified = candidate_keys(header['kid']).any? { |key| key.verify(nil, signature, signing_input) }
        raise_invalid_jwt!('ID token signature is invalid') unless verified

        claims = JSON.parse(base64url_decode(payload_b64))
        ::OpenIDConnect::ResponseObject::IdToken.new(JSON::JWT.new(claims))
      rescue JSON::ParserError, ArgumentError, OpenSSL::PKey::PKeyError => e
        raise_invalid_jwt!("Could not verify ID token (#{e.class})")
      end

      # Ed25519 public keys from the JWKS; the one named by `kid` when given, otherwise all of them.
      def candidate_keys(kid)
        keys = jwks_keys.select { |jwk| jwk['kty'] == 'OKP' && jwk['crv'] == 'Ed25519' }
        keys = keys.select { |jwk| jwk['kid'] == kid } if kid.present? && keys.any? { |jwk| jwk['kid'] == kid }
        keys.map { |jwk| OpenSSL::PKey.new_raw_public_key('ED25519', base64url_decode(jwk['x'])) }
      end

      def jwks_keys
        body = ::OpenIDConnect.http_client.get(client_options.jwks_uri).body
        (body.is_a?(String) ? JSON.parse(body) : body).fetch('keys', [])
      end

      def base64url_decode(value)
        Base64.urlsafe_decode64(value.to_s.ljust((value.to_s.length + 3) / 4 * 4, '='))
      end

      def raise_invalid_jwt!(reason)
        raise CallbackError, error: :invalid_jwt, reason: reason, uri: params['error_uri']
      end
    end
  end
end
