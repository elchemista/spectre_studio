defmodule SpectreStudioWeb.LabLive.Show do
  @moduledoc """
  One bundle's verified timeline.

  The timeline is a stream. A long-lived stream can carry thousands of
  revisions, and the page should not hold all of them in the LiveView's memory
  just to render them once.
  """

  use SpectreStudioWeb, :live_view

  alias SpectreStudio.Lab.Library
  alias SpectreStudio.Lab.Projection

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    case Library.fetch(id) do
      {:ok, bundle} ->
        timeline = Projection.timeline(bundle.playback)
        others = Enum.reject(Library.list(), &(&1.id == id))

        {:ok,
         socket
         |> assign(:page_title, bundle.name)
         |> assign(:active_section, :lab)
         |> assign(:bundle, bundle)
         |> assign(:summary, Projection.completeness_summary(bundle.playback))
         |> assign(:others, others)
         |> assign(:timeline_count, length(timeline))
         |> stream(:timeline, timeline)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "That bundle is no longer loaded.")
         |> push_navigate(to: ~p"/lab")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("drop", _params, socket) do
    :ok = Library.drop(socket.assigns.bundle.id)
    {:noreply, push_navigate(socket, to: ~p"/lab")}
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} connections={@connections} active_section={@active_section}>
      <.header>
        {@bundle.name}
        <:subtitle>{@bundle.stream_id}</:subtitle>
        <:actions>
          <div class="flex flex-wrap gap-2">
            <.button navigate={~p"/lab"}>./bundles</.button>
            <.button phx-click="drop" data-confirm="Forget this bundle?">drop</.button>
          </div>
        </:actions>
      </.header>

      <div class="mt-6 grid gap-6 xl:grid-cols-[24rem_minmax(0,1fr)]">
        <div class="space-y-5">
          <.term_window title="capture">
            <.list>
              <:item title="stream">{@bundle.stream_id}</:item>
              <:item title="size"><span class="tabular">{@bundle.byte_size} B</span></:item>
              <:item title="bundle version">
                <span class="tabular">{@bundle.verification.bundle_version}</span>
              </:item>
            </.list>
            <p class="mt-4 term-out text-[0.75rem] t-dim">{@summary}</p>
            <p class="mt-3 term-comment text-[0.68rem] t-faint">
              Turn-level Input, decision and Effect detail lives in boundary receipts, which Ledger keeps outside a bundle — see docs/STUDIO_BRIDGE.md
            </p>
          </.term_window>

          <.term_window :if={@others != []} title="compare with">
            <ul class="term-list">
              <li :for={other <- @others}>
                <.link
                  navigate={~p"/lab/#{@bundle.id}/diff/#{other.id}"}
                  class="min-w-0 flex-1 truncate t-strong"
                >
                  › {other.name}
                </.link>
              </li>
            </ul>
          </.term_window>
        </div>

        <.term_window title="timeline" status={"#{@timeline_count} entries"}>
          <ol id="timeline" phx-update="stream" class="space-y-3">
            <li :for={{dom_id, entry} <- @streams.timeline} id={dom_id}>
              <div
                :if={entry.kind == :revision}
                class="flex flex-wrap items-baseline gap-x-4 gap-y-1"
              >
                <span class="tabular t-strong">rev {entry.revision}</span>
                <span class="text-[0.72rem] t-dim">{entry.entry_kind}</span>
                <span class="text-[0.72rem] tabular t-faint">
                  {entry.checkpoint_bytes} B · {String.slice(entry.checkpoint_digest, 0, 12)}…
                </span>
              </div>
              <div
                :if={entry.kind == :gap}
                class="flex items-baseline gap-3 border-l border-dashed border-[color:var(--line)] pl-3 text-[0.72rem] t-faint"
              >
                <span aria-hidden="true">╎</span>
                <span>
                  {entry.uncaptured_count} revisions never persisted before rev {entry.checkpoint_revision}
                </span>
              </div>
            </li>
          </ol>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end
end
