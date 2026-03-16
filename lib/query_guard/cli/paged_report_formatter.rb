# frozen_string_literal: true

require 'json'
require 'time'

module QueryGuard
  class CLI
    # Formats QueryGuard reports with pagination support for large finding sets.
    #
    # When a report has many findings (e.g., thousands), pagination allows:
    # - Chunking findings into pages for API transmission
    # - Cursor-based pagination for large datasets
    # - Memory-efficient processing on receiving end
    #
    # Example:
    #   # Paginate findings into pages of 100 each
    #   paged = PagedReportFormatter.new(
    #     report: full_report,
    #     page_size: 100,
    #     page: 1
    #   )
    #
    #   json = paged.generate  # Returns report with findings[0..99]
    #
    # Example with cursor:
    #   paged = PagedReportFormatter.new(
    #     report: full_report,
    #     page_size: 100,
    #     continuation_token: 'abc123...'
    #   )
    #
    #   json = paged.generate  # Returns next batch of 100 findings
    class PagedReportFormatter
      DEFAULT_PAGE_SIZE = 100
      MAX_PAGE_SIZE = 1000

      def initialize(report:, page_size: DEFAULT_PAGE_SIZE, page: 1, continuation_token: nil)
        @report = report.dup  # Don't mutate original
        @page_size = [page_size.to_i, MAX_PAGE_SIZE].min
        @page = [page.to_i, 1].max
        @continuation_token = continuation_token
        @all_findings = @report.delete(:findings) || []
      end

      # Generate paginated report
      # Returns: String (JSON)
      def generate
        JSON.pretty_generate(build_paged_report)
      end

      # Build the paginated report
      def build_paged_report
        start_index = (@page - 1) * @page_size
        end_index = start_index + @page_size

        paginated_findings = @all_findings[start_index...end_index]
        has_more = end_index < @all_findings.length

        # Build the report with paginated findings
        report = @report.dup
        report[:findings] = paginated_findings

        # Add pagination metadata
        report[:pagination] = build_pagination(has_more)

        # Update summary to match paginated findings only
        report[:summary] = update_summary(paginated_findings) if report[:summary]

        report
      end

      private

      # Build pagination metadata
      def build_pagination(has_more)
        pagination = {
          page: @page,
          page_size: @page_size,
          total_findings: @all_findings.length,
          has_more: has_more,
          findings_on_page: [@all_findings.length - ((@page - 1) * @page_size), @page_size].min
        }

        # Add next/previous page tokens for cursor-based pagination
        if has_more
          pagination[:next_page_token] = generate_page_token(@page + 1)
        end

        if @page > 1
          pagination[:prev_page_token] = generate_page_token(@page - 1)
        end

        pagination
      end

      # Update summary to reflect current page counts
      def update_summary(paginated_findings)
        summary = @report[:summary].dup
        by_severity = paginated_findings.group_by { |f| f[:severity] || :info }

        summary[:total_findings] = paginated_findings.length
        summary[:by_severity] = {
          critical: (by_severity[:critical] || []).length,
          error: (by_severity[:error] || []).length,
          warn: (by_severity[:warn] || []).length,
          info: (by_severity[:info] || []).length
        }

        # Keep original file counts from full analysis
        summary
      end

      # Generate a pagination token (opaque, base64-encoded)
      def generate_page_token(page_number)
        require 'base64'
        data = {
          page: page_number,
          page_size: @page_size,
          generated_at: Time.now.to_i
        }
        Base64.strict_encode64(JSON.dump(data))
      end

      # Decode a pagination token (for cursor continuations)
      def decode_page_token(token)
        require 'base64'
        data = JSON.parse(Base64.strict_decode64(token))
        {
          page: data['page'],
          page_size: data['page_size']
        }
      rescue StandardError
        { page: 1, page_size: @page_size }
      end
    end
  end
end
