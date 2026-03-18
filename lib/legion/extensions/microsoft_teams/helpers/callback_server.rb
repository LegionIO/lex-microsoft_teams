# frozen_string_literal: true

require 'socket'
require 'uri'

module Legion
  module Extensions
    module MicrosoftTeams
      module Helpers
        class CallbackServer
          RESPONSE_HTML = <<~HTML
            <html><body style="font-family:sans-serif;text-align:center;padding:40px;">
            <h2>Authentication complete</h2><p>You can close this window.</p></body></html>
          HTML

          attr_reader :port

          def initialize
            @server = nil
            @port = nil
            @result = nil
            @mutex = Mutex.new
            @cv = ConditionVariable.new
          end

          def start
            @server = TCPServer.new('127.0.0.1', 0)
            @port = @server.addr[1]
            @thread = Thread.new { listen }
          end

          def wait_for_callback(timeout: 120)
            @mutex.synchronize do
              @cv.wait(@mutex, timeout) unless @result
              @result
            end
          end

          def shutdown
            @server&.close rescue nil # rubocop:disable Style/RescueModifier
            @thread&.join(2)
            @thread&.kill
          end

          def redirect_uri
            "http://127.0.0.1:#{@port}/callback"
          end

          private

          def listen
            loop do
              client = @server.accept
              request_line = client.gets
              # drain headers
              loop do
                line = client.gets
                break if line.nil? || line.strip.empty?
              end

              if request_line&.include?('/callback?')
                query = request_line.split[1].split('?', 2).last
                params = URI.decode_www_form(query).to_h

                @mutex.synchronize do
                  @result = {
                    code:  params['code'],
                    state: params['state']
                  }
                  @cv.broadcast
                end
              end

              client.print "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n#{RESPONSE_HTML}"
              client.close
              break if @result
            end
          rescue StandardError
            nil # server closed or unexpected error
          end
        end
      end
    end
  end
end
