defmodule JidoAI.Examples.Chat.Telemetry do
  def handle(event, measurements, metadata, %{observer: observer, id: id}) do
    if metadata[:request_id] == id,
      do: send(observer, {:chat_telemetry, event, measurements, metadata})
  end
end
