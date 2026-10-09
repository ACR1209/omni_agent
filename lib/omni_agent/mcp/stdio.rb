require "json"

module OmniAgent
  module MCP
    # stdio transport: newline-delimited JSON-RPC over stdin/stdout. Runs as a
    # local subprocess of the client, so it skips HTTP authentication and takes
    # its principal from the server's `stdio_principal` block instead.
    class Stdio
      # Entry point for `omni_agent mcp` and `rake omni_agent:mcp`. Keeps a
      # private handle on the real stdout for the protocol, then points fd 1
      # at stderr so stray `puts` or logger output cannot corrupt the stream.
      def self.start(server, input: $stdin)
        server_class = MCP.resolve_server_class(server)

        protocol_output = $stdout.dup
        $stdout.flush
        $stdout.reopen($stderr)

        new(server_class, input: input, output: protocol_output).run
      end

      def initialize(server, input:, output:)
        @server_class = MCP.resolve_server_class(server)
        @input = input
        @output = output
      end

      def run
        server = @server_class.new(principal: @server_class.resolve_stdio_principal, transport: :stdio)
        handler = Handler.new(server)

        @input.each_line do |line|
          line = line.strip
          next if line.empty?

          message = begin
            JSON.parse(line)
          rescue JSON::ParserError
            write(jsonrpc: JSONRPC_VERSION, id: nil, error: { code: PARSE_ERROR, message: "Parse error" })
            next
          end

          response = handler.call(message)
          write(response) if response
        end
      end

      private

      def write(payload)
        @output.write("#{JSON.generate(payload)}\n")
        @output.flush
      end
    end
  end
end
