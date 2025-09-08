# Ensure providers are loaded for testing
Application.ensure_all_started(:req_llm)

ExUnit.start()

# Load test helpers
Code.require_file("support/req_llm/test_helpers.ex", __DIR__)
Code.require_file("support/provider_case.ex", __DIR__)
