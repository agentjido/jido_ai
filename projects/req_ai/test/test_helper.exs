# Ensure test support modules are compiled and available
Code.compile_file("test/support/fixture.ex")
Code.compile_file("test/support/provider_case.ex")

# Ensure providers are loaded for testing
Application.ensure_all_started(:req_ai)

ExUnit.start()
