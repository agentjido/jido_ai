require Logger
# Prepare modules for Mimic
Enum.each(
  [
    :telemetry,
    System
  ],
  &Mimic.copy/1
)

# Suite requires debug level for all tests
Logger.configure(level: :debug)

ExUnit.start()

ExUnit.configure(exclude: [:skip])
