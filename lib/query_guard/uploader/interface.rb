# frozen_string_literal: true

module QueryGuard
  module Uploader
    # Abstract interface for report uploaders.
    #
    # All uploaders must implement this interface. This allows:
    # - Pluggable upload strategies (no-op, HTTP, webhook, etc.)
    # - Easy testing with mock uploaders
    # - Future extensibility without changing core code
    #
    # Example:
    #   uploader = QueryGuard::Uploader.for_config(config)
    #   result = uploader.upload(report_json)
    class Interface
      # Upload a JSON report to the configured destination.
      #
      # @param json_report [String] JSON-formatted report string
      # @param metadata [Hash] Optional metadata (report_id, trace_id, etc.)
      #
      # @return [UploadResult] Result object with status and details
      #
      # Should never raise. Always return an UploadResult with success/failure state.
      def upload(json_report, metadata = {})
        raise NotImplementedError, "#{self.class} must implement #upload"
      end

      # Check if this uploader is properly configured and ready.
      #
      # @return [Boolean] true if ready to upload, false otherwise
      def ready?
        raise NotImplementedError, "#{self.class} must implement #ready?"
      end

      # Human-readable name of this uploader.
      #
      # @return [String]
      def name
        raise NotImplementedError, "#{self.class} must implement #name"
      end

      # Get status/diagnostic information for logging.
      #
      # @return [Hash] Status information (target_url, enabled, etc.)
      def status
        raise NotImplementedError, "#{self.class} must implement #status"
      end
    end

    # Result of an upload operation.
    class UploadResult
      attr_reader :success, :uploader_name, :details, :error

      def initialize(success:, uploader_name:, details: {}, error: nil)
        @success = success
        @uploader_name = uploader_name
        @details = details
        @error = error
      end

      def successful?
        @success
      end

      def failed?
        !@success
      end

      def to_h
        {
          success: @success,
          uploader: @uploader_name,
          details: @details,
          error: @error
        }
      end
    end
  end
end
