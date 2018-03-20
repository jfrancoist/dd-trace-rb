require 'spec_helper'

require 'rack'
require 'ddtrace'
require 'ddtrace/contrib/rack/quantize'

RSpec.describe Datadog::Contrib::Rack::Quantize do
  describe '#format_url' do
    subject { described_class.format_url(url, options) }
    let(:options) { {} }

    context 'given a URL' do
      let(:url) { 'http://example.com/path?category_id=1&sort_by=asc#featured' }

      context 'default behavior' do
        it { is_expected.to eq('http://example.com/path?category_id&sort_by') }
      end

      context 'default behavior for an array' do
        let(:url) { 'http://example.com/path?categories[]=1&categories[]=2' }
        it { is_expected.to eq('http://example.com/path?categories[]') }
      end

      context 'with query: show: value' do
        let(:options) { { query: { show: ['category_id'] } } }
        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by') }
      end

      context 'with query: show: :all' do
        let(:options) { { query: { show: :all } } }
        it { is_expected.to eq('http://example.com/path?category_id=1&sort_by=asc') }
      end

      context 'with query: exclude: value' do
        let(:options) { { query: { exclude: ['sort_by'] } } }
        it { is_expected.to eq('http://example.com/path?category_id') }
      end

      context 'with query: exclude: :all' do
        let(:options) { { query: { exclude: :all } } }
        it { is_expected.to eq('http://example.com/path') }
      end

      context 'with show: :all' do
        let(:options) { { fragment: :show } }
        it { is_expected.to eq('http://example.com/path?category_id&sort_by#featured') }
      end
    end
  end

  describe '#format_query_string' do
    subject { described_class.format_query_string(query_string, options) }

    context 'given a query string' do
      context 'and no options' do
        let(:options) { {} }

        context 'with a single parameter' do
          let(:query_string) { 'foo=foo' }
          it { is_expected.to eq('foo') }
        end

        context 'with multiple parameters' do
          let(:query_string) { 'foo=foo&bar=bar' }
          it { is_expected.to eq('foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query_string) { 'foo[]=bar&foo[]=baz' }
          it { is_expected.to eq('foo[]') }
        end

        context 'with object-style parameters' do
          let(:query_string) { 'user[id]=1&user[name]=Nathan' }
          it { is_expected.to eq('user[id]&user[name]') }

          context 'that are complex' do
            let(:query_string) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            it { is_expected.to eq('users[][id]&users[][name]') }
          end
        end
      end

      context 'and a show: :all option' do
        let(:query_string) { 'foo=foo&bar=bar' }
        let(:options) { { show: :all } }
        it { is_expected.to eq(query_string) }
      end

      context 'and a show option' do
        context 'with a single parameter' do
          let(:query_string) { 'foo=foo' }
          let(:options) { { show: ['foo'] } }
          it { is_expected.to eq('foo=foo') }
        end

        context 'with multiple parameters' do
          let(:query_string) { 'foo=foo&bar=bar' }
          let(:options) { { show: ['foo'] } }
          it { is_expected.to eq('foo=foo&bar') }
        end

        context 'with array-style parameters' do
          let(:query_string) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { show: ['foo[]'] } }
          it { is_expected.to eq('foo[]=bar&foo[]=baz') }

          context 'that contains encoded braces' do
            let(:query_string) { 'foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D' }
            it { is_expected.to eq('foo[]=%5Bbar%5D&foo[]=%5Bbaz%5D') }

            context 'that exactly matches the key' do
              let(:query_string) { 'foo[]=foo%5B%5D&foo[]=foo%5B%5D' }
              it { is_expected.to eq('foo[]=foo%5B%5D&foo[]=foo%5B%5D') }
            end
          end
        end

        context 'with object-style parameters' do
          let(:query_string) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { show: ['user[id]'] } }
          it { is_expected.to eq('user[id]=1&user[name]') }

          context 'that are complex' do
            let(:query_string) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { show: ['users[][id]'] } }
            it { is_expected.to eq('users[][id]=1&users[][id]=2&users[][name]') }
          end
        end
      end

      context 'and an exclude: :all option' do
        let(:query_string) { 'foo=foo&bar=bar' }
        let(:options) { { exclude: :all } }
        it { is_expected.to eq('') }
      end

      context 'and an exclude option' do
        context 'with a single parameter' do
          let(:query_string) { 'foo=foo' }
          let(:options) { { exclude: ['foo'] } }
          it { is_expected.to eq('') }
        end

        context 'with multiple parameters' do
          let(:query_string) { 'foo=foo&bar=bar' }
          let(:options) { { exclude: ['foo'] } }
          it { is_expected.to eq('bar') }
        end

        context 'with array-style parameters' do
          let(:query_string) { 'foo[]=bar&foo[]=baz' }
          let(:options) { { exclude: ['foo[]'] } }
          it { is_expected.to eq('') }
        end

        context 'with object-style parameters' do
          let(:query_string) { 'user[id]=1&user[name]=Nathan' }
          let(:options) { { exclude: ['user[name]'] } }
          it { is_expected.to eq('user[id]') }

          context 'that are complex' do
            let(:query_string) { 'users[][id]=1&users[][name]=Nathan&users[][id]=2&users[][name]=Emma' }
            let(:options) { { exclude: ['users[][name]'] } }
            it { is_expected.to eq('users[][id]') }
          end
        end
      end
    end
  end
end
