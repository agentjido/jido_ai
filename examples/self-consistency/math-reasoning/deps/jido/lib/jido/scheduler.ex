defmodule Jido.Scheduler do
  @moduledoc """
  Quantum-based Scheduler for Cron jobs within Jido.

  By default, we attach this to the application supervision tree under the name `:jido_quantum`.

  This scheduler is used by the included `Jido.Sensors.Cron` module to manage cron jobs and emit signals
  on schedule. The Cron provides a high-level interface for:

  - Adding and removing cron jobs
  - Activating and deactivating jobs
  - Running jobs manually
  - Automatically dispatching signals when jobs trigger

  See `Jido.Sensors.Cron` documentation for usage examples and configuration options.
  """

  use Quantum,
    otp_app: :jido
end
