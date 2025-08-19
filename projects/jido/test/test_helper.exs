# Prepare modules for Mimic
Enum.each(
  [
    :telemetry,
    System,
    Req
  ],
  &Mimic.copy/1
)

# Suite requires debug level for all tests
require Logger
Logger.configure(level: :debug)

ExUnit.start()

ExUnit.configure(exclude: [:skip])
