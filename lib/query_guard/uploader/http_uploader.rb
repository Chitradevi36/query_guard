# frozen_string_literal: true

module QueryGuard
  module Uploader
    # HTTP uploader for sending reports to a remote QueryGuard API.
    #
    # This is a template/stub uploader for future SaaS platform integration.
    # It provides the interface for authenticated HTTPS uploads but is not
    # yet connected to a production service.
    #
    # Configuration:
    #   config.uploader_type = 'http'
    #   config.api_base_url = 'https://api.queryguard.example.com'
    #   config.project_key = 'proj-123'
    #   config.api_token = 'token-secret'
    #
    # Use case (future):
    # - Upload findings to hosted QueryGuard platform
    # - Centralized reporting & analytics
    # - Team collaboration on findings
    # - Integration with compliance dashboards
    class HttpUploader < Interface
      # Create HTTP uploader from config.
      #
      # @param config [QueryGuard::Config] Configuration object with API details
      def initialize(config)
        @config = config
        @api_base_url = config.api_base_url
        @project_key = config.project_key
        @api_token = config.api_token
      end

      # Upload JSON report to remote API.
      #
      # @param json_report [String] JSON report string
      # @param metadata [Hash] Additional metadata (tracing, timing, etc.)
      # @return [UploadResult]
      def upload(json_report, metadata = {})
        unless ready?
          return UploadResult.new(
            success: false,
            uploader_name: name,
            error: "HTTP uploader not properly configured (missing #{missing_fields.join(', ')})"
          )
        end

        # Parse report to extract metadata
        report_data = parse_report(json_report)

        perform_upload(json_report, report_data, metadata)
      rescue StandardError => e
        UploadResult.new(
          success: false,
          uploader_name: name,
          error: "Upload failed: #{e.message}"
        )
      end

      # Check if configuration is complete.
      def ready?
        !!(@api_base_url && !@api_base_url.empty? &&
          @project_key && !@project_key.empty? &&
          @api_token && !@api_token.empty?)
      end

      def name
        'http'
      end

      def status
        {
          enabled: ready?,
          mode: 'http',
          api_url: @api_base_url,
          project_key: @project_key,
          description: ready? ? 'Configured for remote API upload' : 'Not configured (missing credentials)'
        }
      end

      private

      # Missing required fields for upload.
      def missing_fields
        fields = []
        fields << 'api_base_url' unless @api_base_url && !@api_base_url.empty?
        fields << 'project_key' unless @project_key && !@project_key.empty?
        fields << 'api_token' unless @api_token && !@api_token.empty?
        fields
      end

      # Extract basic info from JSON report.
      def parse_report(json_str)
        JSON.parse(json_str)
      rescue StandardError
        {}
      end

      # Perform the actual HTTP upload.
      #
      # NOTE: This is a stub implementation. A production version would:
      # - Use Net::HTTP or similar with proper SSL/verify certificate
      # - Handle retries and exponential backoff
      # - Implement request signing/HMAC
      # - Support compression (gzip)
      # - Set proper Content-Type and User-Agent headers
      # - Implement request timeouts and circuit breaks
      #
      # For now, this is a documentation template.
      def perform_upload(json_report, report_data, metadata)
        require 'net/http'
        require 'json'

        url = build_upload_url(report_data)
        request_body = build_request_body(json_report, metadata)

        # Stub: Would make the actual HTTP request here
        # This is intentionally not implemented to prevent accidental
        # API calls during testing or misconfiguration.
        #
        # A production implementation would do something like:
        #   uri = URI(url)
        #   http = Net::HTTP.new(uri.host, uri.port)
        #   http.use_ssl = uri.scheme == 'https'
        #   req = Net::HTTP::Post.new(uri.path)
        #   req['Authorization'] = "Bearer #{@api_token}"
        #   req['Content-Type'] = 'application/json'
        #   response = http.request(req, request_body)
        #
        # But we leave that for when the SaaS platform exists.

        # For now, return a success result indicating what WOULD be sent
        UploadResult.new(
          success: true,
          uploader_name: name,
          details: {
            endpoint: url,
            bytes_sent: request_body.bytesize,
            report_version: report_data['report_version'],
            project_key: @project_key,
            note: 'HTTP uploader is configured but SaaS platform is not yet live'
          }
        )
      end

      # Build the upload endpoint URL.
      def build_upload_url(report_data)
        report_type = report_data['report_type'] || 'analysis'
        base_url = @api_base_url.end_with?('/') ? @api_base_url[0...-1] : @api_base_url
        "#{base_url}/api/v1/projects/#{@project_key}/reports/#{report_type}"
      end

      # Build the request body with headers and payload.
      def build_request_body(json_report, metadata)
        {
          report: JSON.parse(json_report),
          client_metadata: {
            tool_version: QueryGuard::VERSION || 'unknown',
            client_time: Time.now.utc.iso8601,
            trace_id: metadata[:trace_id],
            request_id: metadata[:request_id]
          }
        }.to_json
      end
    end
  end
end
