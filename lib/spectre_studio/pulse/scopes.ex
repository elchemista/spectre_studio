defmodule SpectreStudio.Pulse.Scopes do
  @moduledoc """
  Maps Studio capabilities onto the permission scopes a connection was granted.

  Only two scopes are enforced by Pulse itself: `agent.runtime.read` and
  `agent.runtime.stream`. Every other name here is an application scope — the
  host decides what it means and whether it holds. Studio therefore treats the
  manifest as a statement of intent, shows exactly what was granted and what was
  withheld, and never infers a capability from silence.

  The UI rule that follows from this: an action Studio is not authorised for is
  not rendered at all. Rendering it disabled would tell the operator the action
  exists and they are failing to use it, which is a different and wrong message.
  """

  alias SpectreStudio.Pulse.Manifest

  @capabilities %{
    runtime_read: "agent.runtime.read",
    monitor_stream: "agent.runtime.stream",
    message_send: "agent.message.send",
    control: "agent.control",
    lab_read: "lab.read",
    ledger_read: "ledger.read"
  }

  @type capability ::
          :runtime_read | :monitor_stream | :message_send | :control | :lab_read | :ledger_read

  @doc "All capabilities Studio knows how to ask for."
  @spec capabilities() :: [capability()]
  def capabilities, do: Map.keys(@capabilities)

  @doc "The scope name behind one capability."
  @spec scope(capability()) :: String.t()
  def scope(capability), do: Map.fetch!(@capabilities, capability)

  @doc """
  Whether a manifest grants one capability.

  A connection with no manifest yet grants nothing.
  """
  @spec can?(Manifest.t() | nil, capability()) :: boolean()
  def can?(nil, _capability), do: false

  def can?(%Manifest{granted_scopes: granted}, capability) do
    scope(capability) in granted
  end

  @doc """
  Splits the scopes Studio cares about into granted and withheld.

  Both halves are shown in the UI: a withheld scope explains why a panel is
  missing, and an operator who cannot see the reason will assume a bug.
  """
  @spec partition(Manifest.t() | nil) :: %{granted: [String.t()], withheld: [String.t()]}
  def partition(nil), do: %{granted: [], withheld: Enum.sort(Map.values(@capabilities))}

  def partition(%Manifest{granted_scopes: granted}) do
    known = Map.values(@capabilities)
    interesting = Enum.uniq(known ++ granted)

    %{
      granted: interesting |> Enum.filter(&(&1 in granted)) |> Enum.sort(),
      withheld: interesting |> Enum.reject(&(&1 in granted)) |> Enum.sort()
    }
  end
end
