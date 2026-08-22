defmodule SpectreStudio.Pulse.Scopes do
  @moduledoc """
  Maps Studio capabilities onto the permission scopes a connection was granted.

  Pulse enforces the runtime and operations scope pairs. Cache review, Skill
  creation and Morph proposal scopes are application scopes: the host decides
  what they mean and must enforce them again when it handles the envelope.
  Studio treats every grant as a statement of intent and never infers a
  capability from silence.

  The UI rule that follows from this: an action Studio is not authorised for is
  not rendered at all. Rendering it disabled would tell the operator the action
  exists and they are failing to use it, which is a different and wrong message.
  """

  alias SpectreStudio.Pulse.Manifest

  @capabilities %{
    runtime_read: ["agent.runtime.read"],
    monitor_stream: ["agent.runtime.read", "agent.runtime.stream"],
    operations_read: ["agent.operations.read"],
    operations_stream: ["agent.operations.read", "agent.operations.stream"],
    message_send: ["agent.message.send"],
    semantic_cache_read: ["agent.semantic_cache.read"],
    semantic_cache_promote: ["agent.semantic_cache.promote"],
    skill_create: ["spectre.skill.runtime.mount"],
    morph_create: ["spectre.morph.propose"],
    control: ["agent.control"],
    lab_read: ["lab.read"],
    ledger_read: ["ledger.read"]
  }

  @type capability ::
          :runtime_read
          | :monitor_stream
          | :operations_read
          | :operations_stream
          | :message_send
          | :semantic_cache_read
          | :semantic_cache_promote
          | :skill_create
          | :morph_create
          | :control
          | :lab_read
          | :ledger_read

  @doc "All capabilities Studio knows how to ask for."
  @spec capabilities() :: [capability()]
  def capabilities, do: Map.keys(@capabilities)

  @doc "The complete scope set required by one capability."
  @spec required_scopes(capability()) :: [String.t()]
  def required_scopes(capability), do: Map.fetch!(@capabilities, capability)

  @doc """
  Whether a manifest grants one capability.

  A connection with no manifest yet grants nothing.
  """
  @spec can?(Manifest.t() | nil, capability()) :: boolean()
  def can?(nil, _capability), do: false

  def can?(%Manifest{granted_scopes: granted}, capability) do
    Enum.all?(required_scopes(capability), &(&1 in granted))
  end

  @doc "Whether a manifest grants at least one capability from a set."
  @spec any?(Manifest.t() | nil, [capability()]) :: boolean()
  def any?(manifest, capabilities), do: Enum.any?(capabilities, &can?(manifest, &1))

  @doc """
  Splits the scopes Studio cares about into granted and withheld.

  Both halves are shown in the UI: a withheld scope explains why a panel is
  missing, and an operator who cannot see the reason will assume a bug.
  """
  @spec partition(Manifest.t() | nil) :: %{granted: [String.t()], withheld: [String.t()]}
  def partition(nil), do: %{granted: [], withheld: known_scopes()}

  def partition(%Manifest{granted_scopes: granted}) do
    known = known_scopes()
    interesting = Enum.uniq(known ++ granted)

    %{
      granted: interesting |> Enum.filter(&(&1 in granted)) |> Enum.sort(),
      withheld: interesting |> Enum.reject(&(&1 in granted)) |> Enum.sort()
    }
  end

  @spec known_scopes() :: [String.t()]
  defp known_scopes do
    @capabilities
    |> Map.values()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
