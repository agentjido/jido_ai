# ServerSentEvents

[![CI](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml/badge.svg)](https://github.com/benjreinhart/server_sent_events/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/server_sent_events.svg)](https://github.com/benjreinhart/server_sent_events/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/server_sent_events.svg)](https://hex.pm/benjreinhart/server_sent_events)

Lightweight, ultra-fast Server Sent Event parser for Elixir.

This module fully conforms to the official [Server Sent Events specification](https://html.spec.whatwg.org/multipage/server-sent-events.html#parsing-an-event-stream) with a comprehensive [test suite](https://github.com/benjreinhart/server_sent_events/blob/main/test/server_sent_events_test.exs).

## Usage

```elixir
{events, rest} = ServerSentEvents.parse("event: event\ndata: {\"complete\":true}\n\n")
IO.inspect(events)   # [%{event: "event", data: "{\"complete\":true}\n"}]
IO.inspect(rest)     # ""
```

Parsing a chunk containing zero or more events followed by an incomplete event returns the incomplete data.

```elixir
{events, buffer} = ServerSentEvents.parse("event: event\ndata: {\"complete\":")
IO.inspect(events)   # []
IO.inspect(buffer)   # "event: event\ndata: {\"complete\":"

{events, buffer} = ServerSentEvents.parse(buffer <> "true}\n\nevent: event\ndata: {")
IO.inspect(events)   # [%{event: "event", data: "{\"complete\":true}\n"}]
IO.inspect(buffer)   # "event: event\ndata: {"

{events, rest} = ServerSentEvents.parse(buffer <> "\"key\":\"value\"}\n\n")
IO.inspect(events)   # [%{event: "event", data: "{\"key\":\"value\"}\n"}]
IO.inspect(rest)     # ""
```

This can be useful for streaming environments where a single event may not reliably arrive in one chunk.

## Real world example

AI providers like OpenAI and Anthropic stream AI generated messages using Server Sent Events.
This module can handle parsing the server sent events, returning a list of maps. For example,
we can parse a streaming response from Anthropic:

```elixir
Req.post("https://api.anthropic.com/v1/messages",
  json: request,
  into: fn {:data, data}, {req, res} ->
    buffer = Request.get_private(req, :sse_buffer, "")
    {events, buffer} = ServerSentEvents.parse(buffer <> data)
    Request.put_private(req, :sse_buffer, buffer)

    if events != [] do
      # Do something with events, e.g., send to a process consuming them.
      send(pid, {:events, events})
    end

    {:cont, {req, res}}
  end,
  headers: %{
    "x-api-key" => api_key(),
    "anthropic-version" => "2023-06-01"
  }
)
```

The first chunk from Anthropic tends to contain a couple of messages that look something like the following when parsed by this module:

```elixir
# Parsing first chunk from Anthropic
{events, ""} = ServerSentEvents.parse(chunk)
IO.inspect(events)
# [
#   %{
#     data: "{\"type\":\"message_start\",\"message\":{\"id\":\"msg_01LAFhYgKvtBB5ac5n41oyDn\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-3-5-sonnet-20241022\",\"content\":[],\"stop_reason\":null,\"stop_sequence\":null,\"usage\":{\"input_tokens\":12,\"output_tokens\":2}}        }",
#     event: "message_start"
#   },
#   %{
#     data: "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}         }",
#     event: "content_block_start"
#   },
#   %{data: "{\"type\": \"ping\"}", event: "ping"},
#   %{
#     data: "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Here's\"}          }",
#     event: "content_block_delta"
#   }
# ]
```

This is typically followed by filtering out unwanted events and JSON parsing the `data` field of meaningful events.

## Installation

The package can be installed by adding `server_sent_events` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:server_sent_events, "~> 0.2.0"}
  ]
end
```
