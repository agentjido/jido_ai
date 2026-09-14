defmodule JidoAI.Examples.Telemetry do
  @moduledoc "Forwards example telemetry events to the test process."

  def handle(event, measurements, metadata, pid) do
    send(pid, {:linear_telemetry, event, measurements, metadata})
  end
end
