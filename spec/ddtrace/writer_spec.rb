require 'spec_helper'

require 'ddtrace'
require 'json'

RSpec.describe Datadog::Writer do
  include HttpHelpers

  before(:each) { WebMock.enable! }
  after(:each) do
    WebMock.reset!
    WebMock.disable!
  end

  describe 'instance' do
    subject(:writer) { described_class.new(options) }
    let(:options) { {} }

    describe 'behavior' do
      describe '#initialize' do
        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::PrioritySampler) }

          context 'and default transport options' do
            it do
              expect(Datadog::HTTPTransport).to receive(:new) do |hostname, port, options|
                expect(hostname).to eq(described_class::HOSTNAME)
                expect(port).to eq(described_class::PORT)
                expect(options).to be_a_kind_of(Hash)
                expect(options[:api_version]).to eq(Datadog::HTTPTransport::V4)
              end

              expect(writer.priority_sampler).to be(sampler)
              sampling_method = described_class.instance_method(:sampling_updater)
              expect(writer.instance_variable_get(:@response_callback).source_location).to eq(sampling_method.source_location)
            end
          end

          context 'and custom transport options' do
            let(:options) { super().merge!(transport_options: transport_options) }
            let(:transport_options) { { api_version: api_version, response_callback: response_callback } }
            let(:api_version) { double('API version') }
            let(:response_callback) { double('response callback') }

            it do
              expect(Datadog::HTTPTransport).to receive(:new) do |hostname, port, options|
                expect(hostname).to eq(described_class::HOSTNAME)
                expect(port).to eq(described_class::PORT)
                expect(options).to include(
                  api_version: api_version,
                  response_callback: response_callback
                )
              end
              expect(writer.priority_sampler).to be(sampler)
              expect(writer.instance_variable_get(:@response_callback)).to be(response_callback)
            end
          end
        end
      end

      describe '#send_spans' do
        subject(:result) { writer.send_spans(traces, writer.transport) }
        let(:traces) { get_test_traces(1) }

        context 'with priority sampling' do
          let(:options) { { priority_sampler: sampler } }
          let(:sampler) { instance_double(Datadog::Sampler) }

          context 'when the transport uses' do
            let(:options) { super().merge!(transport_options: { api_version: api_version, response_callback: callback }) }
            let(:callback) { s = spy; Proc.new { |*args| s.call(*args) } }
            let(:spy) { double('callback spy') }
            
            let!(:request) { stub_request(:post, endpoint).to_return(response) }
            let(:endpoint) { "#{Datadog::Writer::HOSTNAME}:#{Datadog::Writer::PORT}/#{api_version}/traces" }
            let(:response) { { body: body } }
            let(:body) { 'body' }

            shared_examples_for 'an API version' do
              context 'that succeeds' do
                before(:each) do
                  expect(spy).to receive(:call).with(a_kind_of(Net::HTTPOK), a_kind_of(Hash)) do |response, api|
                    expect(api[:version]).to eq(api_version)
                  end
                end

                it do
                  is_expected.to be true
                  assert_requested(request)
                end
              end

              context 'but falls back to v3' do
                let(:response) { super().merge!(status: 404) }
                let!(:fallback_request) { stub_request(:post, fallback_endpoint).to_return(body: body) }
                let(:fallback_endpoint) { "#{Datadog::Writer::HOSTNAME}:#{Datadog::Writer::PORT}/#{fallback_version}/traces" }
                let(:body) { 'body' }

                before(:each) do
                  call_count = 0
                  allow(spy).to receive(:call).with(a_kind_of(Net::HTTPResponse), a_kind_of(Hash)) do |response, api|
                    call_count += 1
                    if call_count == 1
                      expect(response).to be_a_kind_of(Net::HTTPNotFound)
                      expect(api[:version]).to eq(api_version)
                    elsif call_count == 2
                      expect(response).to be_a_kind_of(Net::HTTPOK)
                      expect(api[:version]).to eq(fallback_version)
                    end
                  end
                end

                it do
                  is_expected.to be true
                  assert_requested(request)
                end
              end
            end

            context 'API v4' do
              it_behaves_like 'an API version' do
                let(:api_version) { Datadog::HTTPTransport::V4 }
                let(:fallback_version) { Datadog::HTTPTransport::V3 }
              end
            end

            context 'API v3' do
              it_behaves_like 'an API version' do
                let(:api_version) { Datadog::HTTPTransport::V3 }
                let(:fallback_version) { Datadog::HTTPTransport::V2 }
              end
            end
          end
        end
      end

      describe '#sampling_updater' do
        subject(:result) { writer.send(:sampling_updater, response, api) }

        let(:options) { { priority_sampler: sampler } }
        let(:sampler) { instance_double(Datadog::PrioritySampler) }
        let(:api) { double('api') }

        context 'given a response that' do
          context 'isn\'t OK' do
            let(:response) { double('failure response') }
            it { is_expected.to be nil }
          end

          context 'is OK' do
            let(:response) { mock_http_request(method: :post, body: body)[:response] }

            context 'and is API v4' do
              let(:api) { { version: Datadog::HTTPTransport::V4 } }
              let(:service_rates) { { 'service:a,env:test' => 0.1, 'service:b,env:test' => 0.5 } }
              let(:body) { service_rates.to_json }

              it do
                expect(sampler).to receive(:update).with(service_rates)
                is_expected.to be true
              end
            end

            context 'and is API v3' do
              let(:api) { { version: Datadog::HTTPTransport::V3 } }
              let(:body) { 'OK' }

              it do
                expect(sampler).to_not receive(:update)
                is_expected.to be false
              end
            end
          end
        end
      end
    end
  end
end
