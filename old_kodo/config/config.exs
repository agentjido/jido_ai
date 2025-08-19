import Config

# Configure logger to reduce noise during tests
if Mix.env() == :test do
  config :logger, level: :warning
end
