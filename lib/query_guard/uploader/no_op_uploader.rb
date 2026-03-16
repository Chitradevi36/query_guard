# frozen_string_literal: true

module QueryGuard
  module Uploader
    # No-op uploader that discards reports (default behavior).
    #
    # This is the default uploader when no remote API is configured.
    # It silently discards reports, making the upload system completely optional.
    #
    # Use case:
    # - Local development without remote API
    # - CI/CD without SaaS platform integration
    # - Organizations that don't want to send data to external services
    class NoOpUploader < Interface
      def initialize(config = nil)
        @config = config
      end

      # Always succeeds, does nothing.
      def upload(json_report, metadata = {})
        UploadResult.new(
          success: true,
          uploader_name: name,
          details: { discarded: true, bytes: json_report.bytesize }
        )
      end

      # Always ready (no configuration needed).
      def ready?
        true
      end

      def name
        'no-op'
      end

      def status
        {
          enabled: false,
          mode: 'no-op',
          description: 'Reports are discarded (upload disabled)'
        }
      end
    end
  end
end
