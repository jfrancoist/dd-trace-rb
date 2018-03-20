require 'cgi'

module Datadog
  module Contrib
    module Rack
      # Quantize contains Rack-specic quantization tools.
      module Quantize
        module_function

        def format_url(url, options = {})
          options ||= {}

          URI.parse(url).tap do |uri|
            # Format the query string
            if uri.query
              query = format_query_string(uri.query, options[:query])
              uri.query = (!query.nil? && query.empty? ? nil : query)
            end

            # Remove any URI framents
            uri.fragment = nil unless options[:fragment] == :show
          end.to_s
        end

        def format_query_string(query_string, options = {})
          options ||= {}
          options[:show] = options[:show] || []
          options[:exclude] = options[:exclude] || []

          # Short circuit if query string is meant to exclude everything
          return '' if options[:exclude] == :all

          CGI.parse(query_string).collect do |key, value|
            if options[:exclude].include?(key)
              nil
            else
              value = (options[:show] == :all || options[:show].include?(key) ? value : nil)
              query = URI.encode_www_form(key => value)

              # Encoding the params will also encode the key.
              # Convert the key back afterwards, to preseve integrity.
              encoded_key = key.gsub('[', '%5B').gsub(']', '%5D')
              query.gsub(/(?:^|&)\K#{Regexp.escape(encoded_key)}/, key)
            end
          end.flatten.compact.join('&').strip
        end
      end
    end
  end
end
