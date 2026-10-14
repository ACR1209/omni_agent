require "json"
require "net/http"
require "openssl"
require "uri"

module OmniAgent
  module MCP
    module OAuth
      # Minimal JSON client for the authorization server (JWKS, introspection).
      module HTTPClient
        OPEN_TIMEOUT = 5
        READ_TIMEOUT = 5

        NETWORK_ERRORS = [
          IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, URI::InvalidURIError
        ].freeze

        module_function

        def get_json(url)
          uri = URI.parse(url.to_s)
          request(uri, Net::HTTP::Get.new(uri))
        end

        def post_form_json(url, form, basic_auth: nil)
          uri = URI.parse(url.to_s)
          post = Net::HTTP::Post.new(uri)
          post.set_form_data(form)
          post.basic_auth(*basic_auth) if basic_auth
          request(uri, post)
        end

        def request(uri, http_request)
          http_request["accept"] = "application/json"

          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(http_request)
          end

          unless response.is_a?(Net::HTTPSuccess)
            raise VerificationError, "#{http_request.method} #{uri} returned HTTP #{response.code}"
          end

          JSON.parse(response.body.to_s)
        rescue JSON::ParserError, *NETWORK_ERRORS => e
          raise VerificationError, "#{http_request.method} #{uri} failed: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
