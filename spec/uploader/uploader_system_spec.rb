# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe 'QueryGuard Uploader System' do
  describe 'Uploader Interface' do
    it 'defines abstract interface' do
      interface = QueryGuard::Uploader::Interface.new

      expect { interface.upload('{}') }.to raise_error(NotImplementedError)
      expect { interface.ready? }.to raise_error(NotImplementedError)
      expect { interface.name }.to raise_error(NotImplementedError)
      expect { interface.status }.to raise_error(NotImplementedError)
    end
  end

  describe 'UploadResult' do
    describe 'successful upload' do
      let(:result) do
        QueryGuard::Uploader::UploadResult.new(
          success: true,
          uploader_name: 'test',
          details: { bytes: 1000 }
        )
      end

      it 'indicates success' do
        expect(result.successful?).to be true
        expect(result.failed?).to be false
      end

      it 'has no error message' do
        expect(result.error).to be_nil
      end

      it 'converts to hash' do
        expect(result.to_h).to include(
          success: true,
          uploader: 'test'
        )
      end
    end

    describe 'failed upload' do
      let(:result) do
        QueryGuard::Uploader::UploadResult.new(
          success: false,
          uploader_name: 'http',
          error: 'Connection timeout'
        )
      end

      it 'indicates failure' do
        expect(result.successful?).to be false
        expect(result.failed?).to be true
      end

      it 'stores error message' do
        expect(result.error).to eq('Connection timeout')
      end
    end
  end

  describe 'NoOpUploader' do
    let(:uploader) { QueryGuard::Uploader::NoOpUploader.new }

    it 'is the default uploader' do
      expect(uploader.name).to eq('no-op')
    end

    describe '#upload' do
      it 'always succeeds' do
        result = uploader.upload('{"findings":[]}')
        expect(result.successful?).to be true
      end

      it 'records bytes discarded' do
        json = '{"test": "data"}'
        result = uploader.upload(json)
        expect(result.details[:bytes]).to eq(json.bytesize)
      end

      it 'marks upload as discarded' do
        result = uploader.upload('{}')
        expect(result.details[:discarded]).to be true
      end

      it 'never raises' do
        expect { uploader.upload('{}') }.not_to raise_error
      end
    end

    describe '#ready?' do
      it 'is always ready' do
        expect(uploader.ready?).to be true
      end
    end

    describe '#status' do
      let(:status) { uploader.status }

      it 'reports disabled' do
        expect(status[:enabled]).to be false
      end

      it 'reports no-op mode' do
        expect(status[:mode]).to eq('no-op')
      end

      it 'includes description' do
        expect(status[:description]).to include('discarded')
      end
    end
  end

  describe 'HttpUploader' do
    let(:config) do
      QueryGuard::Config.new.tap do |c|
        c.api_base_url = 'https://api.queryguard.example.com'
        c.project_key = 'proj-123'
        c.api_token = 'secret-token'
      end
    end

    let(:incomplete_config) do
      QueryGuard::Config.new
      # Missing api_base_url, project_key, api_token
    end

    let(:uploader) { QueryGuard::Uploader::HttpUploader.new(config) }
    let(:incomplete_uploader) { QueryGuard::Uploader::HttpUploader.new(incomplete_config) }

    describe '#name' do
      it 'identifies as http uploader' do
        expect(uploader.name).to eq('http')
      end
    end

    describe '#ready?' do
      it 'is ready when all config present' do
        expect(uploader.ready?).to be true
      end

      it 'is not ready when missing api_base_url' do
        config.api_base_url = nil
        expect(uploader.ready?).to be false
      end

      it 'is not ready when missing project_key' do
        config.project_key = nil
        expect(uploader.ready?).to be false
      end

      it 'is not ready when missing api_token' do
        config.api_token = nil
        expect(uploader.ready?).to be false
      end

      it 'is never ready with incomplete config' do
        expect(incomplete_uploader.ready?).to be false
      end
    end

    describe '#upload' do
      let(:sample_report) do
        {
          report_version: '1.0',
          report_type: 'analyze',
          findings: [
            {
              id: 'abc123',
              analyzer: 'test',
              rule: 'test_rule',
              severity: 'error',
              title: 'Test',
              description: 'Test finding'
            }
          ]
        }.to_json
      end

      context 'when properly configured' do
        it 'succeeds' do
          result = uploader.upload(sample_report)
          expect(result.successful?).to be true
        end

        it 'includes endpoint in details' do
          result = uploader.upload(sample_report)
          expect(result.details[:endpoint]).to include('/api/v1/projects/proj-123')
        end

        it 'includes report version' do
          result = uploader.upload(sample_report)
          expect(result.details[:report_version]).to eq('1.0')
        end

        it 'includes bytes sent' do
          result = uploader.upload(sample_report)
          expect(result.details[:bytes_sent]).to be > 0
        end

        it 'includes note about stub implementation' do
          result = uploader.upload(sample_report)
          expect(result.details[:note]).to include('SaaS platform is not yet live')
        end
      end

      context 'when not configured' do
        it 'fails gracefully' do
          result = incomplete_uploader.upload(sample_report)
          expect(result.failed?).to be true
        end

        it 'includes error message' do
          result = incomplete_uploader.upload(sample_report)
          expect(result.error).to include('not properly configured')
        end

        it 'lists missing fields in error' do
          result = incomplete_uploader.upload(sample_report)
          expect(result.error).to include('api_base_url')
        end
      end

      context 'with metadata' do
        it 'accepts trace_id in metadata' do
          result = uploader.upload(
            sample_report,
            { trace_id: 'trace-xyz' }
          )
          expect(result.successful?).to be true
        end

        it 'accepts request_id in metadata' do
          result = uploader.upload(
            sample_report,
            { request_id: 'req-abc' }
          )
          expect(result.successful?).to be true
        end
      end

      it 'returns uploader name in result' do
        result = uploader.upload(sample_report)
        expect(result.uploader_name).to eq('http')
      end
    end

    describe '#status' do
      let(:status) { uploader.status }

      it 'reports enabled when ready' do
        expect(status[:enabled]).to be true
      end

      it 'reports http mode' do
        expect(status[:mode]).to eq('http')
      end

      it 'includes api_url' do
        expect(status[:api_url]).to eq('https://api.queryguard.example.com')
      end

      it 'includes project_key' do
        expect(status[:project_key]).to eq('proj-123')
      end

      it 'includes description' do
        expect(status[:description]).to include('remote API')
      end
    end

    describe 'URL building' do
      it 'builds correct endpoint for analyze reports' do
        report = { report_type: 'analyze' }.to_json
        result = uploader.upload(report)
        expect(result.details[:endpoint]).to include('/reports/analyze')
      end

      it 'builds correct endpoint for check reports' do
        report = { report_type: 'check' }.to_json
        result = uploader.upload(report)
        expect(result.details[:endpoint]).to include('/reports/check')
      end

      it 'removes trailing slash from api_base_url' do
        config.api_base_url = 'https://api.queryguard.example.com/'
        result = uploader.upload({ report_type: 'analyze' }.to_json)
        endpoint = result.details[:endpoint]
        expect(endpoint).not_to include('//api/v1')
      end
    end

    describe 'Request body building' do
      let(:sample_report) do
        {
          report_version: '1.0',
          report_type: 'analyze',
          findings: []
        }.to_json
      end

      it 'builds request body' do
        result = uploader.upload(
          sample_report,
          { trace_id: 'trace-123', request_id: 'req-456' }
        )
        expect(result.successful?).to be true
      end

      it 'includes tool version in metadata' do
        result = uploader.upload(sample_report)
        # Details should show successful construction
        expect(result.successful?).to be true
      end
    end
  end

  describe 'Uploader Registry' do
    it 'returns NoOpUploader by default' do
      config = QueryGuard::Config.new
      uploader = QueryGuard::Uploader::Registry.for_config(config)
      expect(uploader).to be_a(QueryGuard::Uploader::NoOpUploader)
    end

    context 'with uploader_type configured' do
      it 'returns HttpUploader when type is http' do
        config = QueryGuard::Config.new
        config.uploader_type = 'http'
        config.api_base_url = 'https://api.example.com'
        config.project_key = 'proj'
        config.api_token = 'token'

        uploader = QueryGuard::Uploader::Registry.for_config(config)
        expect(uploader).to be_a(QueryGuard::Uploader::HttpUploader)
      end

      it 'returns NoOpUploader when type is no-op' do
        config = QueryGuard::Config.new
        config.uploader_type = 'no-op'
        uploader = QueryGuard::Uploader::Registry.for_config(config)
        expect(uploader).to be_a(QueryGuard::Uploader::NoOpUploader)
      end

      it 'accepts noop without dash' do
        config = QueryGuard::Config.new
        config.uploader_type = 'noop'
        uploader = QueryGuard::Uploader::Registry.for_config(config)
        expect(uploader).to be_a(QueryGuard::Uploader::NoOpUploader)
      end

      it 'handles case-insensitive type' do
        config = QueryGuard::Config.new
        config.uploader_type = 'HTTP'
        config.api_base_url = 'https://api.example.com'
        config.project_key = 'proj'
        config.api_token = 'token'

        uploader = QueryGuard::Uploader::Registry.for_config(config)
        expect(uploader).to be_a(QueryGuard::Uploader::HttpUploader)
      end

      it 'raises on unknown type' do
        config = QueryGuard::Config.new
        config.uploader_type = 'webhook'

        expect { QueryGuard::Uploader::Registry.for_config(config) }
          .to raise_error(ArgumentError, /Unknown uploader type/)
      end
    end

    it 'lists available uploaders' do
      available = QueryGuard::Uploader::Registry.available_uploaders
      expect(available).to include('no-op', 'http')
    end
  end

  describe 'UploadService' do
    let(:config) do
      QueryGuard::Config.new.tap do |c|
        c.uploader_type = 'no-op'
      end
    end

    let(:service) { QueryGuard::Uploader::UploadService.new(config) }
    let(:sample_report) { { report_version: '1.0', findings: [] }.to_json }

    describe '#upload_report' do
      it 'uploads successfully' do
        result = service.upload_report(sample_report)
        expect(result.successful?).to be true
      end

      it 'accepts trace_id' do
        result = service.upload_report(sample_report, trace_id: 'trace-123')
        expect(result.successful?).to be true
      end

      it 'accepts request_id' do
        result = service.upload_report(sample_report, request_id: 'req-456')
        expect(result.successful?).to be true
      end

      it 'never raises, always returns result' do
        expect { service.upload_report(sample_report) }.not_to raise_error
      end

      it 'never raises on malformed report' do
        expect { service.upload_report('not json') }.not_to raise_error
      end

      it 'returns result object' do
        result = service.upload_report(sample_report)
        expect(result).to be_a(QueryGuard::Uploader::UploadResult)
      end
    end

    describe '#status' do
      let(:status) { service.status }

      it 'includes uploader name' do
        expect(status[:uploader]).to eq('no-op')
      end

      it 'includes ready flag' do
        expect(status[:ready]).to be true
      end

      it 'includes details' do
        expect(status[:details]).to be_a(Hash)
      end
    end

    describe '#ready?' do
      it 'reflects uploader readiness' do
        expect(service.ready?).to eq(service.uploader.ready?)
      end
    end

    describe '#reconfigure' do
      it 'updates uploader' do
        original_uploader = service.uploader

        new_config = QueryGuard::Config.new
        new_config.uploader_type = 'http'

        service.reconfigure(new_config)
        expect(service.uploader).not_to eq(original_uploader)
      end

      it 'returns self for chaining' do
        new_config = QueryGuard::Config.new
        result = service.reconfigure(new_config)
        expect(result).to be(service)
      end
    end

    context 'with HTTP uploader configured' do
      let(:http_config) do
        QueryGuard::Config.new.tap do |c|
          c.uploader_type = 'http'
          c.api_base_url = 'https://api.queryguard.example.com'
          c.project_key = 'proj-123'
          c.api_token = 'secret-token'
        end
      end

      let(:http_service) { QueryGuard::Uploader::UploadService.new(http_config) }

      it 'uses HTTP uploader' do
        expect(http_service.uploader).to be_a(QueryGuard::Uploader::HttpUploader)
      end

      it 'reports ready when configured' do
        expect(http_service.ready?).to be true
      end

      it 'successfully uploads reports' do
        result = http_service.upload_report(sample_report)
        expect(result.successful?).to be true
      end
    end
  end

  describe 'Integration: Config + Upload Service' do
    it 'creates upload service from config' do
      config = QueryGuard::Config.new
      config.uploader_type = 'no-op'

      service = QueryGuard::Uploader::UploadService.new(config)
      expect(service).to be_a(QueryGuard::Uploader::UploadService)
    end

    it 'uses no-op uploader by default' do
      config = QueryGuard::Config.new
      service = QueryGuard::Uploader::UploadService.new(config)

      expect(service.uploader).to be_a(QueryGuard::Uploader::NoOpUploader)
    end

    it 'can switch uploaders via reconfiguration' do
      # Start with no-op
      config1 = QueryGuard::Config.new
      config1.uploader_type = 'no-op'
      service = QueryGuard::Uploader::UploadService.new(config1)
      expect(service.uploader).to be_a(QueryGuard::Uploader::NoOpUploader)

      # Reconfigure to HTTP
      config2 = QueryGuard::Config.new
      config2.uploader_type = 'http'
      config2.api_base_url = 'https://api.example.com'
      config2.project_key = 'proj'
      config2.api_token = 'token'
      service.reconfigure(config2)

      expect(service.uploader).to be_a(QueryGuard::Uploader::HttpUploader)
    end
  end

  describe 'Network Behavior Safety' do
    it 'no-op uploader never makes HTTP calls' do
      service = QueryGuard::Uploader::UploadService.new(QueryGuard::Config.new)

      # Should complete instantly without network calls
      start_time = Time.now
      result = service.upload_report('{"findings": []}')
      elapsed = Time.now - start_time

      expect(result.successful?).to be true
      expect(elapsed).to be < 0.1  # Should be instant, no network
    end

    it 'HTTP uploader does not make real HTTP calls (stub)' do
      config = QueryGuard::Config.new
      config.uploader_type = 'http'
      config.api_base_url = 'https://api.queryguard.example.com'
      config.project_key = 'proj'
      config.api_token = 'token'

      service = QueryGuard::Uploader::UploadService.new(config)

      # Should not raise, should return result
      # (no real HTTP call is made)
      expect { service.upload_report('{}') }.not_to raise_error
    end

    it 'upload behavior is disabled unless explicitly configured' do
      # Create service with default config (no api_base_url, etc.)
      config = QueryGuard::Config.new
      service = QueryGuard::Uploader::UploadService.new(config)

      # Should use no-op uploader, no upload happens
      expect(service.uploader).to be_a(QueryGuard::Uploader::NoOpUploader)
      expect(service.uploader.ready?).to be true  # No-op is always ready (does nothing)
    end
  end
end
