# frozen_string_literal: true

module QueryGuard
  module Uploader
    # Service for uploading analysis reports.
    #
    # This is the main public API for uploading reports. It:
    # - Coordinates with configured uploader
    # - Handles errors gracefully
    # - Provides logging/status information
    # - Never blocks or raises exceptions
    #
    # Usage:
    #   service = QueryGuard::Uploader::UploadService.new(config)
    #   result = service.upload_report(json_string, trace_id: '...')
    #   puts result.to_h if result.failed?
    class UploadService
      def initialize(config = nil)
        @config = config || QueryGuard.config
        @uploader = Registry.for_config(@config)
      end

      # Upload a JSON report from the configured JSON reporter.
      #
      # @param json_report [String] JSON string from JsonReporter#generate
      # @param trace_id [String] Optional trace ID for distributed tracing
      # @param request_id [String] Optional request ID
      # @return [UploadResult] Result object (never raises)
      def upload_report(json_report, trace_id: nil, request_id: nil)
        metadata = {}
        metadata[:trace_id] = trace_id if trace_id
        metadata[:request_id] = request_id if request_id

        @uploader.upload(json_report, metadata)
      rescue StandardError => e
        # Always return graceful result, never raise
        UploadResult.new(
          success: false,
          uploader_name: @uploader.name,
          error: "Unexpected error: #{e.message}"
        )
      end

      # Get status information about the current uploader.
      #
      # @return [Hash] Status information
      def status
        {
          uploader: @uploader.name,
          ready: @uploader.ready?,
          details: @uploader.status
        }
      end

      # Check if uploader is ready and configured.
      #
      # @return [Boolean]
      def ready?
        @uploader.ready?
      end

      # Get the current uploader instance.
      #
      # @return [Interface] The active uploader
      def uploader
        @uploader
      end

      # Reconfigure with a new config object.
      #
      # @param config [QueryGuard::Config]
      # @return [self]
      def reconfigure(config)
        @config = config
        @uploader = Registry.for_config(@config)
        self
      end
    end
  end
end
