require "openssl"
require "base64"
require "cinch/sasl/mechanism"

module Cinch
  module SASL
    class DH_Blowfish < Mechanism
      class << self
        # @return [Array<Number, Number, Number>] p, g and y for DH
        def unpack_payload(payload)
          pgy     = []
          payload = payload.dup

          3.times do
            size = payload.unpack("n").first
            payload.slice!(0, 2)
            pgy << payload.unpack("a#{size}").first
            payload.slice!(0, size)
          end

          pgy.map {|i| OpenSSL::BN.new(i, 2).to_i}
        end

        # @param [String] user
        # @param [String] password
        # @param [String] payload
        # @return [String]
        def generate(user, password, payload)
          data = Base64.decode64(payload).force_encoding("ASCII-8BIT")

          p, g, y = unpack_payload(data)

          dh      = DiffieHellman.new(p, g, 23)
          pub_key = dh.generate
          secret  = OpenSSL::BN.new(dh.secret(y).to_s).to_s(2)
          public  = OpenSSL::BN.new(pub_key.to_s).to_s(2)

          # Pad password so its length is a multiple of the cipher block size
          password << "\0"
          password << "." * (8 - (password.size % 8))

          crypted = ""
          cipher = OpenSSL::Cipher.new("BF")

          while password.size > 0 do
            # We have to reinitialize this every time because for OpenSSL, "BF" is synonynmous with "BF-CBC", and we do not want CBC
            cipher.reset
            cipher.key_len = 32 # OpenSSL's default of 16 doesn't work
            cipher.encrypt
            cipher.key = secret

            clear = password.slice!(0, 8)
            crypted << cipher.update(clear) # we do not want the content of cipher.final
          end

          answer = [public.bytesize, public, user, crypted].pack("na*Z*a*")
          Base64.strict_encode64(answer)
        end
      end
    end
  end
end
