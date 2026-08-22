defmodule SpectreStudio.Lab.Projection do
  @moduledoc """
  Turns a verified playback into something an operator can read.

  One honest limitation shapes this module. A Bundle v1 carries the checkpoint
  chain, and Lab keeps the checkpoints opaque — it does not decode Instance
  internals. So the Input, decision and Effect detail of a Turn is *not*
  derivable from a bundle alone; it lives in the boundary receipts, which Ledger
  keeps outside the bundle and which reach Studio only through the host bridge.

  What this projection therefore renders is the verified revision timeline with
  its gaps stated as gaps. A gap means Spectre coalesced checkpoint writes and
  the intermediate revisions were never persisted. It is not lost history and
  the UI must never imply that it is.
  """

  alias Spectre.Lab.Playback

  @doc "The timeline of a bundle: persisted revisions with gap markers between them."
  @spec timeline(Playback.t()) :: [map()]
  def timeline(%Playback{frames: frames} = playback) do
    gaps = Map.get(Playback.completeness(playback), :revision_gaps, [])

    frames
    |> Enum.flat_map(fn frame ->
      [
        %{
          id: "revision-#{frame.revision}",
          kind: :revision,
          index: frame.index,
          revision: frame.revision,
          expected_revision: frame.expected_revision,
          checkpoint_digest: frame.checkpoint_digest,
          blob_digest: frame.blob_digest,
          entry_digest: frame.entry_digest,
          checkpoint_bytes: byte_size(frame.checkpoint),
          stream_key: frame.entry.stream_key,
          entry_kind: frame.entry.kind
        }
      ] ++ gap_after(gaps, frame.revision)
    end)
  end

  defp gap_after(gaps, revision) do
    gaps
    |> Enum.filter(&(Map.get(&1, :after_revision) == revision))
    |> Enum.map(fn gap ->
      %{
        id: "gap-#{Map.get(gap, :after_revision)}",
        kind: :gap,
        after_revision: Map.get(gap, :after_revision),
        checkpoint_revision: Map.get(gap, :checkpoint_revision),
        uncaptured_count: Map.get(gap, :uncaptured_count)
      }
    end)
  end

  @doc "A one-line summary of what the bundle actually captured."
  @spec completeness_summary(Playback.t()) :: String.t()
  def completeness_summary(%Playback{} = playback) do
    completeness = Playback.completeness(playback)
    persisted = length(Map.get(completeness, :persisted_revisions, []))
    gaps = length(Map.get(completeness, :revision_gaps, []))

    uncaptured =
      completeness
      |> Map.get(:revision_gaps, [])
      |> Enum.map(&Map.get(&1, :uncaptured_count, 0))
      |> Enum.sum()

    case gaps do
      0 ->
        "#{persisted} persisted revisions, no gaps"

      _some ->
        "#{persisted} persisted revisions · #{gaps} gaps covering #{uncaptured} " <>
          "revisions that were never written — coalesced checkpoints, not lost history"
    end
  end

  @doc "Compares two loaded playbacks."
  @spec compare(Playback.t(), Playback.t()) :: {:ok, map()} | {:error, term()}
  def compare(%Playback{} = left, %Playback{} = right) do
    case Spectre.Lab.diff(left, right) do
      {:ok, report} -> {:ok, diff_rows(report)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp diff_rows(report) do
    revisions =
      (report.left_revisions ++ report.right_revisions)
      |> Enum.uniq()
      |> Enum.sort()

    rows =
      Enum.map(revisions, fn revision ->
        kind =
          cond do
            revision in report.changed_revisions -> :changed
            revision in report.left_only -> :removed
            revision in report.right_only -> :added
            true -> :same
          end

        %{id: "diff-#{revision}", revision: revision, kind: kind}
      end)

    %{
      status: report.status,
      common_prefix_count: report.common_prefix_count,
      common_head_revision: report.common_head_revision,
      first_divergence: Enum.find(rows, &(&1.kind != :same)),
      rows: rows
    }
  end
end
