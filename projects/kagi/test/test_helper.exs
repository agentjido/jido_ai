ExUnit.start()

# Ensure the application is started for tests
{:ok, _} = Application.ensure_all_started(:kagi)
