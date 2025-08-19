# Configure test exclusions
ExUnit.configure(
  exclude: [
    # Exclude integration tests by default
    :integration,
    # Exclude slow tests by default
    :slow,
    # Exclude tests that hit real APIs
    :external_api,
    # Exclude flaky tests by default
    :flaky
  ]
)

ExUnit.start(capture_log: true)

# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)
