defmodule SpectreStudioWeb.LabLive.Diff do
  @moduledoc """
  Two verified timelines for the same stream, side by side.

  The comparison runs through `assign_async/3`: it is a pure computation over
  two whole chains, and the page should show its frame before that finishes
  rather than after.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.StudioComponents

  alias SpectreStudio.Lab.Library
  alias SpectreStudio.Lab.Projection

  @impl Phoenix.LiveView
  def mount(%{"id" => id, "other" => other_id}, _session, socket) do
    with {:ok, left} <- Library.fetch(id),
         {:ok, right} <- Library.fetch(other_id) do
      {:ok,
       socket
       |> assign(:page_title, "diff")
       |> assign(:active_section, :lab)
       |> assign(:left, left)
       |> assign(:right, right)
       |> assign_async(:diff, fn -> compare(left, right) end)}
    else
      :error ->
        {:ok,
         socket
         |> put_flash(:error, "One of those bundles is no longer loaded.")
         |> push_navigate(to: ~p"/lab")}
    end
  end

  defp compare(left, right) do
    case Projection.compare(left.playback, right.playback) do
      {:ok, diff} -> {:ok, %{diff: diff}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} connections={@connections} active_section={@active_section}>
      <.header>
        diff
        <:subtitle>{@left.name} → {@right.name}</:subtitle>
        <:actions>
          <.button navigate={~p"/lab/#{@left.id}"}>./bundle</.button>
        </:actions>
      </.header>

      <div class="mt-6">
        <.async_result :let={diff} assign={@diff}>
          <:loading>
            <.term_window title="diff" status="comparing">
              <p class="term-out text-[0.8rem] t-dim">
                walking both checkpoint chains <.cursor />
              </p>
            </.term_window>
          </:loading>

          <:failed :let={reason}>
            <.term_window title="diff" status="failed">
              <p class="term-out text-[0.8rem] t-fail">could not compare: {inspect(reason)}</p>
            </.term_window>
          </:failed>

          <.term_window title="diff" status={to_string(diff.status)}>
            <.list>
              <:item title="status">{diff.status}</:item>
              <:item title="common prefix">
                <span class="tabular">{diff.common_prefix_count} revisions</span>
              </:item>
              <:item title="first divergence">
                {if diff.first_divergence,
                  do: "revision #{diff.first_divergence.revision}",
                  else: "none"}
              </:item>
            </.list>

            <div class="term-diff mt-5">
              <.diff_row :for={row <- diff.rows} kind={row.kind}>
                revision {row.revision}
              </.diff_row>
            </div>
          </.term_window>
        </.async_result>
      </div>
    </Layouts.app>
    """
  end
end
