defmodule SpectreStudio.Pulse.Boot do
  @moduledoc """
  Brings stored connections up at start-up.

  A separate task rather than work inside `SpectreStudio.Pulse`, so a vault that
  cannot be read, or an endpoint that refuses the first connection, delays
  nothing and takes nothing else down with it. Only specs marked `auto_connect`
  open a socket; the rest are merely present.
  """

  use Task, restart: :transient

  @doc false
  @spec start_link(term()) :: {:ok, pid()}
  def start_link(_opts), do: Task.start_link(&run/0)

  @doc false
  @spec run() :: :ok
  def run, do: SpectreStudio.Pulse.start_stored()
end
