ExUnit.start()

# Configure logger to only show warnings and errors during tests
require Logger
Logger.configure(level: :warning)

# Configure ExUnit to capture logs by default and enable async tests
ExUnit.configure(capture_log: true)

# Ensure test support modules are compiled and available
Code.ensure_compiled!(Kodo.Case)
