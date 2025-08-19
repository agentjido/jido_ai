Logger.configure(level: :error)
ExUnit.start(capture_log: true, exclude: [:live_eval])
