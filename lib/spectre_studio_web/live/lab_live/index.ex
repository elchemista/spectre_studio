defmodule SpectreStudioWeb.LabLive.Index do
  @moduledoc """
  The bundle library: what is loaded, and the door to load more.

  Verification is not free — Ledger walks and re-hashes the whole checkpoint
  chain — so a load runs as an async task and the page reports it as in flight
  rather than freezing the LiveView until it finishes.
  """

  use SpectreStudioWeb, :live_view

  alias Phoenix.LiveView.AsyncResult
  alias SpectreStudio.Config
  alias SpectreStudio.Lab.Library

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    bundles = Library.list()

    {:ok,
     socket
     |> assign(:page_title, "lab")
     |> assign(:active_section, :lab)
     |> assign(:bundle_count, length(bundles))
     # Starts as a settled "nothing yet" rather than an untouched struct:
     # async_result/1 has no branch for a result that is neither loading, failed
     # nor ok.
     |> assign(:load, AsyncResult.ok(nil))
     |> stream(:bundles, bundles)
     |> allow_upload(:bundle,
       # A Ledger bundle has no registered media type and travels under whatever
       # name the exporter gave it. Filtering by extension would reject valid
       # bundles; the real gate is Ledger's verification in `Library.load/2`.
       accept: :any,
       max_entries: 1,
       max_file_size: Config.get().max_bundle_bytes
     )}
  end

  @impl Phoenix.LiveView
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("upload", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :bundle, fn %{path: path}, entry ->
        {:ok, {entry.client_name, File.read!(path)}}
      end)

    case uploaded do
      [{name, contents}] ->
        {:noreply,
         socket
         |> assign(:load, AsyncResult.loading())
         |> start_async(:load_bundle, fn -> Library.load(name, contents) end)}

      [] ->
        {:noreply,
         assign(socket, :load, AsyncResult.failed(AsyncResult.ok(nil), "no file selected"))}
    end
  end

  def handle_event("drop", %{"id" => id}, socket) do
    :ok = Library.drop(id)

    {:noreply,
     socket
     |> stream_delete_by_dom_id(:bundles, "bundles-#{id}")
     |> update(:bundle_count, &max(&1 - 1, 0))}
  end

  @impl Phoenix.LiveView
  def handle_async(:load_bundle, {:ok, {:ok, bundle}}, socket) do
    {:noreply,
     socket
     |> assign(:load, AsyncResult.ok(bundle))
     |> stream_insert(:bundles, bundle, at: 0)
     |> update(:bundle_count, &(&1 + 1))
     |> push_navigate(to: ~p"/lab/#{bundle.id}")}
  end

  def handle_async(:load_bundle, {:ok, {:error, reason}}, socket) do
    {:noreply, assign(socket, :load, AsyncResult.failed(AsyncResult.ok(nil), describe(reason)))}
  end

  def handle_async(:load_bundle, {:exit, reason}, socket) do
    {:noreply, assign(socket, :load, AsyncResult.failed(AsyncResult.ok(nil), describe(reason)))}
  end

  defp describe({:too_large, limit}), do: "bundle exceeds the #{div(limit, 1_000_000)} MB limit"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} connections={@connections} active_section={@active_section}>
      <.header>
        lab
        <:subtitle>verified checkpoint playback, offline</:subtitle>
      </.header>

      <div class="mt-5 space-y-1 border-l-2 border-[color:var(--line-strong)] pl-4 text-[0.75rem] leading-6 t-dim">
        <p>
          A Ledger bundle is a <span class="t-strong">trusted</span>
          artefact: decoding it may load a module named by a valid checkpoint. Load only bundles you produced.
        </p>
        <p>
          Playback covers the checkpoints Spectre actually persisted. It is not deterministic replay, and it does not reproduce model or external effects.
        </p>
      </div>

      <div class="mt-6 grid gap-6 xl:grid-cols-2">
        <.term_window title="load bundle">
          <form id="bundle-upload" phx-submit="upload" phx-change="validate" class="space-y-4">
            <.live_file_input upload={@uploads.bundle} class="term-field" />

            <.async_result :let={bundle} assign={@load}>
              <:loading>
                <p class="term-out text-[0.75rem] t-dim">
                  verifying the checkpoint chain <.cursor />
                </p>
              </:loading>
              <:failed :let={reason}>
                <p class="term-out text-[0.75rem] t-fail">{reason}</p>
              </:failed>
              <p :if={bundle} class="term-out text-[0.75rem] t-ok">verified {bundle.name}</p>
            </.async_result>

            <p :for={error <- upload_errors(@uploads.bundle)} class="term-out text-[0.75rem] t-fail">
              {upload_error(error)}
            </p>

            <.button variant="primary">verify and load</.button>
          </form>
        </.term_window>

        <.term_window title="bundles" status={"#{@bundle_count}"}>
          <p :if={@bundle_count == 0} class="term-comment text-[0.78rem] t-faint">
            nothing loaded yet
          </p>

          <ul id="bundles" phx-update="stream" class="term-list">
            <li :for={{dom_id, bundle} <- @streams.bundles} id={dom_id}>
              <.link navigate={~p"/lab/#{bundle.id}"} class="min-w-0 flex-1 truncate t-strong">
                › {bundle.name}
              </.link>
              <span class="flex items-center gap-3">
                <span class="tabular t-faint">{bundle.byte_size} B</span>
                <button
                  type="button"
                  phx-click="drop"
                  phx-value-id={bundle.id}
                  class="cursor-pointer t-faint transition hover:t-strong"
                >
                  drop
                </button>
              </span>
            </li>
          </ul>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  defp upload_error(:too_large), do: "file is larger than the configured limit"
  defp upload_error(:not_accepted), do: "unsupported file type"
  defp upload_error(:too_many_files), do: "one bundle at a time"
  defp upload_error(error), do: to_string(error)
end
