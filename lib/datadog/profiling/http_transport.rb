# frozen_string_literal: true

require_relative "../core/transport/ext"
require_relative "../core/telemetry/logger"

module Datadog
  module Profiling
    # Used to report profiling data to Datadog.
    # Methods prefixed with _native_ are implemented in `http_transport.c`
    class HttpTransport
      attr_reader :exporter_configuration

      def initialize(agent_settings:, site:, api_key:, upload_timeout_seconds:)
        @upload_timeout_milliseconds = (upload_timeout_seconds * 1_000).to_i

        @exporter_configuration =
          if agentless?(site, api_key)
            [:agentless, site, api_key].freeze
          else
            [:agent, agent_settings.url].freeze
          end

        status, result = validate_exporter(exporter_configuration)

        raise(ArgumentError, "Failed to initialize transport: #{result}") if status == :error
      end

      def export(flush)
        status, result = do_export(
          exporter_configuration: exporter_configuration,
          upload_timeout_milliseconds: @upload_timeout_milliseconds,

          # why "timespec"?
          # libdatadog represents time using POSIX's struct timespec, see
          # https://www.gnu.org/software/libc/manual/html_node/Time-Types.html
          # aka it represents the seconds part separate from the nanoseconds part
          start_timespec_seconds: flush.start.tv_sec,
          start_timespec_nanoseconds: flush.start.tv_nsec,
          finish_timespec_seconds: flush.finish.tv_sec,
          finish_timespec_nanoseconds: flush.finish.tv_nsec,

          pprof_file_name: flush.pprof_file_name,
          pprof_data: flush.pprof_data,
          code_provenance_file_name: flush.code_provenance_file_name,
          code_provenance_data: flush.code_provenance_data,

          tags_as_array: flush.tags_as_array,
          internal_metadata_json: flush.internal_metadata_json,

          info_json: flush.info_json
        )

        if status == :ok
          if (200..299).cover?(result)
            Datadog.logger.debug("Successfully reported profiling data")
            true
          else
            Datadog.logger.error(
              "Failed to report profiling data (#{config_without_api_key}): " \
              "server returned unexpected HTTP #{result} status code"
            )
            Datadog::Core::Telemetry::Logger.error(
              "Failed to report profiling data: unexpected HTTP #{result} status code"
            )
            false
          end
        else
          Datadog.logger.error("Failed to report profiling data (#{config_without_api_key}): #{result}")
          Datadog::Core::Telemetry::Logger.error("Failed to report profiling data")
          false
        end
      end

      private

      def agentless?(site, api_key)
        site && api_key && Core::Environment::VariableHelpers.env_to_bool(Profiling::Ext::ENV_AGENTLESS, false)
      end

      def validate_exporter(exporter_configuration)
        self.class._native_validate_exporter(exporter_configuration)
      end

      def do_export(
        exporter_configuration:,
        upload_timeout_milliseconds:,
        start_timespec_seconds:,
        start_timespec_nanoseconds:,
        finish_timespec_seconds:,
        finish_timespec_nanoseconds:,
        pprof_file_name:,
        pprof_data:,
        code_provenance_file_name:,
        code_provenance_data:,
        tags_as_array:,
        internal_metadata_json:,
        info_json:
      )
        self.class._native_do_export(
          exporter_configuration,
          upload_timeout_milliseconds,
          start_timespec_seconds,
          start_timespec_nanoseconds,
          finish_timespec_seconds,
          finish_timespec_nanoseconds,
          pprof_file_name,
          pprof_data,
          code_provenance_file_name,
          code_provenance_data,
          tags_as_array,
          internal_metadata_json,
          info_json,
        )
      end

      def config_without_api_key
        "#{exporter_configuration[0]}: #{exporter_configuration[1]}"
      end
    end
  end
end
