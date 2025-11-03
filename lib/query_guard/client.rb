# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module QueryGuard
  class Client
    DEFAULT_TIMEOUT = 5 # seconds

    def initialize(base_url:, api_key:, project:, env:)
      @base_url = base_url.sub(%r{/\z}, "") rescue ''
      @api_key  = api_key
      @project  = project
      @env      = env
    end

    # Example call used by your Subscriber/Middleware
    def post(path, payload)
      uri = URI.parse("#{@base_url}#{path}")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{@api_key}" if @api_key
      req.body = JSON.generate(payload.merge(project: @project, env: @env))

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = DEFAULT_TIMEOUT
      http.read_timeout = DEFAULT_TIMEOUT

      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        warn "[QueryGuard] POST #{uri} -> #{res.code} #{res.body}"
      end
      res
    rescue => e
      warn "[QueryGuard] HTTP error: #{e.class}: #{e.message}"
      nil
    end
  end
end
