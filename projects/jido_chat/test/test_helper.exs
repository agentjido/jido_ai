# In test/test_helper.exs
Application.ensure_all_started(:jido)
Application.ensure_all_started(:jido_chat)
ExUnit.start(exclude: [:e2e])
