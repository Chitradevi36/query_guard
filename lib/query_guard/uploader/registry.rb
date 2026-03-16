# frozen_string_literal: true

module QueryGuard
  module Uploader
    # Registry for selecting and instantiating uploaders.
    #
    # Provides a factory pattern for creating the appropriate uploader
    # based on configuration.
    class Registry
      # Get the appropriate uploader for the given configuration.
      #
      # @param config [QueryGuard::Config] Configuration object
      # @return [Interface] An uploader instance
      def self.for_config(config)
        uploader_type = config.uploader_type&.downcase || 'no-op'

        case uploader_type
        when 'http'
          HttpUploader.new(config)
        when 'no-op', 'noop', 'none', 'disabled', nil
          NoOpUploader.new(config)
        else
          raise ArgumentError, "Unknown uploader type: #{uploader_type}. " \
                               "Supported: 'http', 'no-op' (default)"
        end
      end

      # List all available uploader types.
      def self.available_uploaders
        {
          'no-op' => 'Local/no-op mode (default, no upload)',
          'http' => 'HTTP API upload (for future SaaS platform)'
        }
      end
    end
  end
end
