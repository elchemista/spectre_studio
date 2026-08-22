defmodule SpectreStudioWeb.ConnectionLive.Form do
  @moduledoc """
  Creating and editing one Pulse endpoint.

  A page of its own rather than a panel folded into the dashboard: the form owns
  a credential, and keeping it on its own route means the token field is never
  part of a screen that is left open while watching a system.
  """

  use SpectreStudioWeb, :live_view

  alias SpectreStudio.Pulse
  alias SpectreStudio.Pulse.ConnectionSpec

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    socket =
      socket
      |> assign(:active_section, :connections)
      |> assign(:errors, [])

    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "new connection")
    |> assign(:editing, nil)
    |> assign(:form, blank_form())
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Pulse.fetch_spec(id) do
      {:ok, spec} ->
        socket
        |> assign(:page_title, "edit #{spec.label}")
        |> assign(:editing, spec)
        |> assign(:active_connection, id)
        |> assign(:form, form_for_spec(spec))

      :error ->
        socket
        |> put_flash(:error, "That connection no longer exists.")
        |> push_navigate(to: ~p"/")
    end
  end

  @impl Phoenix.LiveView
  def handle_event("save", %{"connection" => params}, socket) do
    params =
      case socket.assigns.editing do
        %ConnectionSpec{id: id} -> Map.put(params, "id", id)
        nil -> params
      end

    case Pulse.save(params) do
      {:ok, spec} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connection #{spec.label} saved.")
         |> push_navigate(to: ~p"/connections/#{spec.id}")}

      {:error, errors} when is_list(errors) ->
        {:noreply, assign(socket, :errors, errors)}

      {:error, :vault_key_missing} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No vault key configured — Studio will not write a token to disk unencrypted. " <>
             "Set STUDIO_VAULT_KEY and try again."
         )}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Could not save: #{inspect(reason)}")}
    end
  end

  defp blank_form do
    to_form(%{"label" => "", "url" => "wss://", "token" => "", "verify_tls" => "true"},
      as: :connection
    )
  end

  defp form_for_spec(%ConnectionSpec{} = spec) do
    to_form(
      %{
        "label" => spec.label,
        "url" => spec.url,
        "token" => spec.token || "",
        "verify_tls" => to_string(spec.verify_tls),
        "auto_connect" => to_string(spec.auto_connect)
      },
      as: :connection
    )
  end

  defp error_for(errors, field) do
    Enum.find_value(errors, fn {key, message} -> if key == field, do: message end)
  end

  @impl Phoenix.LiveView
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.header>
        {if @editing, do: "edit connection", else: "new connection"}
        <:subtitle>a Pulse endpoint and the credential that reaches it</:subtitle>
        <:actions>
          <.button navigate={~p"/"}>cancel</.button>
        </:actions>
      </.header>

      <div class="mt-6 max-w-3xl">
        <.term_window title="connection">
          <.form for={@form} id="connection-form" phx-submit="save" class="grid gap-5 md:grid-cols-2">
            <div>
              <.input field={@form[:label]} label="label" placeholder="prod-eu" />
              <p :if={error_for(@errors, :label)} class="mt-2 term-out text-[0.72rem] t-fail">
                label {error_for(@errors, :label)}
              </p>
            </div>
            <div>
              <.input
                field={@form[:url]}
                label="endpoint"
                placeholder="wss://host/pulse/websocket"
              />
              <p :if={error_for(@errors, :url)} class="mt-2 term-out text-[0.72rem] t-fail">
                endpoint {error_for(@errors, :url)}
              </p>
            </div>
            <div class="md:col-span-2">
              <.input
                field={@form[:token]}
                type="password"
                label="token"
                autocomplete="off"
                placeholder="sent as ?token= on the socket URL"
              />
              <p class="mt-2 term-comment text-[0.68rem] t-faint">
                sealed with AES-256-GCM before it touches disk — a Studio without a vault key refuses to store it
              </p>
            </div>
            <div class="flex flex-col gap-3 md:col-span-2">
              <.input field={@form[:verify_tls]} type="checkbox" label="verify TLS certificate" />
              <.input field={@form[:auto_connect]} type="checkbox" label="connect at start-up" />
            </div>
            <div class="md:col-span-2">
              <.button variant="primary">save connection</.button>
            </div>
          </.form>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end
end
