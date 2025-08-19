# defmodule Mix.Tasks.Jido.Ai.Playground do
#   @shortdoc "Launch Phoenix Playground chat interface for Jido AI"
#   @moduledoc """
#   Launches a Phoenix Playground web interface for testing Jido AI with multiple providers,
#   model configurations, structured data generation, and analytics.

#   ## Usage

#       mix jido.ai.playground
#       mix jido.ai.playground --model openrouter:anthropic/claude-3.5-sonnet
#       mix jido.ai.playground --port 4000

#   ## Options

#     * `--model` - Model to use (default: "openrouter:openai/gpt-oss-20b:free")
#     * `--port` - Port to run the server on (default: 4001)

#   """

#   use Mix.Task

#   @impl Mix.Task
#   def run(args) do
#     Application.ensure_all_started(:jido_ai)

#     {opts, _args_list, _} =
#       OptionParser.parse(args,
#         switches: [
#           model: :string,
#           port: :integer
#         ]
#       )

#     default_model =
#       Application.get_env(:jido_ai, :default_model, "openrouter:openai/gpt-oss-20b:free")

#     model = Keyword.get(opts, :model, default_model)
#     port = Keyword.get(opts, :port, 4001)

#     IO.puts("🚀 Starting Jido AI Playground...")
#     IO.puts("Model: #{model}")
#     IO.puts("Port: #{port}")
#     IO.puts("")
#     IO.puts("Open your browser to http://localhost:#{port}")
#     IO.puts("Press Ctrl+C to stop")
#     IO.puts("")

#     PhoenixPlayground.start(
#       live: JidoAI.PlaygroundLive,
#       port: port,
#       live_reload: true
#     )

#     Process.sleep(:infinity)
#   end
# end
