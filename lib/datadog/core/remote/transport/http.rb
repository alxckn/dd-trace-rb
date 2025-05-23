# frozen_string_literal: true

require 'uri'

require_relative '../../environment/container'
require_relative '../../environment/ext'
require_relative '../../transport/ext'
require_relative '../../transport/http/builder'
require_relative '../../transport/http/adapters/net'
require_relative '../../transport/http/adapters/unix_socket'
require_relative '../../transport/http/adapters/test'

# TODO: Improve negotiation to allow per endpoint selection
#
# Since endpoint negotiation happens at the `API::Spec` level there can not be
# a mix of endpoints at various versions or versionless without describing all
# the possible combinations as specs. See http/api.
#
# Below should be:
# require_relative '../../transport/http/api'
require_relative 'http/api'

# TODO: Decouple transport/http
#
# Because a new transport is required for every (API, Client, Transport)
# triplet and endpoints cannot be negotiated independently, there can not be a
# single `default` transport, but only endpoint-specific ones.

module Datadog
  module Core
    module Remote
      module Transport
        # Namespace for HTTP transport components
        module HTTP
          # NOTE: Due to... legacy reasons... This class likes having a default `AgentSettings` instance to fall back to.
          # Because we generate this instance with an empty instance of `Settings`, the resulting `AgentSettings` below
          # represents only settings specified via environment variables + the usual defaults.
          #
          # DO NOT USE THIS IN NEW CODE, as it ignores any settings specified by users via `Datadog.configure`.
          DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS = Datadog::Core::Configuration::AgentSettingsResolver.call(
            Datadog::Core::Configuration::Settings.new,
            logger: nil,
          )

          module_function

          # Builds a new Transport::HTTP::Client
          def new(klass, &block)
            Core::Transport::HTTP::Builder.new(
              api_instance_class: API::Instance, &block
            ).to_transport(klass)
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def root(
            agent_settings: DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS,
            **options
          )
            new(Core::Remote::Transport::Negotiation::Transport) do |transport|
              transport.adapter(agent_settings)
              transport.headers(default_headers)

              apis = API.defaults

              transport.api API::ROOT, apis[API::ROOT]

              # Apply any settings given by options
              unless options.empty?
                transport.default_api = options[:api_version] if options.key?(:api_version)
                transport.headers options[:headers] if options.key?(:headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def v7(
            agent_settings: DO_NOT_USE_ENVIRONMENT_AGENT_SETTINGS,
            **options
          )
            new(Core::Remote::Transport::Config::Transport) do |transport|
              transport.adapter(agent_settings)
              transport.headers default_headers

              apis = API.defaults

              transport.api API::V7, apis[API::V7]

              # Apply any settings given by options
              unless options.empty?
                transport.default_api = options[:api_version] if options.key?(:api_version)
                transport.headers options[:headers] if options.key?(:headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end
          end

          def default_headers
            {
              Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1',
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION =>
                Datadog::Core::Environment::Ext::LANG_VERSION,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
                Datadog::Core::Environment::Ext::LANG_INTERPRETER,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
                Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION
            }.tap do |headers|
              # Add container ID, if present.
              container_id = Datadog::Core::Environment::Container.container_id
              headers[Datadog::Core::Transport::Ext::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
              # Sending this header to the agent will disable metrics computation (and billing) on the agent side
              # by pretending it has already been done on the library side.
              if Datadog.configuration.appsec.standalone.enabled
                headers[Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS] = 'yes'
              end
            end
          end

          def default_adapter
            Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
          end

          # Add adapters to registry
          Core::Transport::HTTP::Builder::REGISTRY.set(
            Datadog::Core::Transport::HTTP::Adapters::Net,
            Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
          )
          Core::Transport::HTTP::Builder::REGISTRY.set(
            Datadog::Core::Transport::HTTP::Adapters::Test,
            Datadog::Core::Transport::Ext::Test::ADAPTER
          )
          Core::Transport::HTTP::Builder::REGISTRY.set(
            Datadog::Core::Transport::HTTP::Adapters::UnixSocket,
            Datadog::Core::Configuration::Ext::Agent::UnixSocket::ADAPTER
          )
        end
      end
    end
  end
end
