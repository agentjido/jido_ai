ExUnit.start()

# Ensure Ash is started for tests
Application.ensure_all_started(:ash)

# Create test config to disable protocol consolidation during tests
# This prevents "Inspect protocol already consolidated" warnings
ExUnit.configure(capture_log: true)

# Set IO options to reduce noise
Application.put_env(:logger, :level, :warning)

# Suppress module redefinition warnings in test environment
# These occur due to dynamic module generation during tests
Code.compiler_options(ignore_module_conflict: true)
