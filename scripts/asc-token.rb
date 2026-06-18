#!/usr/bin/env ruby
# Mint App Store Connect API JWT (ES256) i ispiši na stdout.
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (.p8)
require 'jwt'
require 'openssl'

key_id    = ENV.fetch('ASC_KEY_ID')
issuer_id = ENV.fetch('ASC_ISSUER_ID')
key_path  = ENV.fetch('ASC_KEY_PATH')

ec_key = OpenSSL::PKey.read(File.read(key_path))
now = Time.now.to_i
payload = {
  iss: issuer_id,
  iat: now,
  exp: now + 1200, # ≤20 min
  aud: 'appstoreconnect-v1'
}
puts JWT.encode(payload, ec_key, 'ES256', { kid: key_id, typ: 'JWT' })
