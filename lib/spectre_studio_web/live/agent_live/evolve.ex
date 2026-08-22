defmodule SpectreStudioWeb.AgentLive.Evolve do
  @moduledoc """
  Per-Agent Skill inventory and governed Morph proposal authoring.

  Runtime Skill changes go through Morph. A request creates and evaluates a
  candidate; it never implies approval or activation, which remain independent
  host commits.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudio.Pulse.StudioBridge
  alias SpectreStudioWeb.AgentLive.Shell

  @requirements {:any, [:skill_read, :morph_create]}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :evolve, @requirements) do
      {:ok, socket} ->
        socket =
          socket
          |> assign(:skills, [])
          |> assign(:pending, %{})
          |> assign(:error, nil)
          |> assign(:result, nil)
          |> assign(:morph_form, morph_form())

        if connected?(socket) and Scopes.can?(socket.assigns.connection.manifest, :skill_read),
          do: send(self(), :load_skills)

        {:ok, socket}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("refresh-skills", _params, socket) do
    case StudioBridge.list_skills(socket.assigns.connection.id, socket.assigns.agent.address) do
      {:ok, envelope} ->
        pending = Map.put(socket.assigns.pending, envelope["id"], :skills_list)
        {:noreply, assign(socket, pending: pending, error: nil, result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  def handle_event("propose-morph", %{"morph" => params}, socket) do
    with {:ok, subject} <- required(params, "subject"),
         {:ok, actor} <- required(params, "by"),
         {:ok, reason} <- required(params, "reason"),
         {:ok, mount_id} <- required(params, "mount_id"),
         {:ok, match} <- required(params, "match"),
         {:ok, reply} <- required(params, "reply") do
      attrs = %{
        "subject" => subject,
        "by" => actor,
        "reason" => reason,
        "mount_id" => mount_id,
        "match" => match,
        "reply" => reply,
        "scopes" => comma_list(params["scopes"]),
        "token_cap" => positive_integer(params["token_cap"]),
        "action" => params["action"] || "mount"
      }

      send_bridge(socket, :morph_propose, morph_form(params), fn ->
        StudioBridge.propose_morph_skill(
          socket.assigns.connection.id,
          socket.assigns.agent.address,
          attrs
        )
      end)
    else
      {:error, reason} -> {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  @impl Phoenix.LiveView
  def handle_info(:load_skills, socket) do
    case StudioBridge.list_skills(socket.assigns.connection.id, socket.assigns.agent.address) do
      {:ok, envelope} ->
        pending = Map.put(socket.assigns.pending, envelope["id"], :skills_list)
        {:noreply, assign(socket, pending: pending, error: nil, result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  def handle_info({:envelope, _connection_id, envelope}, socket) do
    case StudioBridge.response(envelope, socket.assigns.pending) do
      {:ok, request_id, :skills_list, data} ->
        skills = data |> Map.get("skills", []) |> Enum.filter(&is_map/1)

        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:skills, skills)
         |> assign(:result, "loaded #{length(skills)} Skills")}

      {:ok, request_id, :morph_propose, data} ->
        {:noreply,
         socket
         |> finish(request_id)
         |> assign(:result, Jason.encode!(data, pretty: true))}

      {:error, request_id, reason} ->
        {:noreply, socket |> finish(request_id) |> assign(:error, describe(reason))}

      :unrelated ->
        {:noreply, socket}
    end
  end

  def handle_info({:connection_status, _id, _status}, socket),
    do: {:noreply, Shell.reload(socket)}

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl Phoenix.LiveView
  def render(assigns) do
    assigns =
      assigns
      |> assign(:can_read_skills?, Scopes.can?(assigns.connection.manifest, :skill_read))
      |> assign(:can_propose_morph?, Scopes.can?(assigns.connection.manifest, :morph_create))

    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.agent_header connection={@connection} agent={@agent} tab={@tab} />

      <div class="mt-6 space-y-6">
        <.term_window title="Skill inventory" status={"#{length(@skills)} mounted"}>
          <div class="flex flex-wrap items-start justify-between gap-4">
            <p class="max-w-3xl text-[0.76rem] leading-6 t-dim">
              Compiled and governed runtime Skills belong to the Agent Definition. Refresh reads
              the host inventory; it does not infer Skills from routes or prompts.
              <span :if={!@can_read_skills?} class="block mt-2 t-fail">
                inventory locked — missing spectre.skill.read
              </span>
            </p>
            <.button :if={@can_read_skills?} type="button" phx-click="refresh-skills">
              refresh Skills
            </.button>
          </div>

          <p :if={@skills == []} class="mt-5 term-comment text-[0.78rem] t-faint">
            no Skills loaded
          </p>
          <div class="mt-5 grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            <article :for={skill <- @skills} class="border border-[var(--border)] p-4">
              <p class="term-label">{skill["id"]}</p>
              <p class="mt-2 break-all text-[0.72rem] t-dim">{skill["module"]}</p>
              <p class="mt-2 text-[0.7rem] t-faint">
                {skill["origin"]} · definition v{skill["definition_version"]}
              </p>
            </article>
          </div>
        </.term_window>

        <div>
          <.term_window :if={@can_propose_morph?} title="new Morph proposal" status="evaluate only">
            <p class="mb-5 text-[0.75rem] leading-6 t-dim">
              Creates a reply-only Skill proposal and asks the host to evaluate it against
              protected cases. Approval and activation are intentionally not part of this action.
            </p>

            <.form for={@morph_form} id="morph-form" phx-submit="propose-morph" class="space-y-4">
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@morph_form[:subject]} label="subject" placeholder="account-123" />
                <.input
                  field={@morph_form[:action]}
                  type="select"
                  label="change"
                  options={[{"mount Skill", "mount"}, {"replace Skill", "replace"}]}
                />
                <.input field={@morph_form[:by]} label="actor" placeholder="actor:operator" />
                <.input field={@morph_form[:mount_id]} label="mount id" placeholder="refunds" />
              </div>
              <.input
                field={@morph_form[:reason]}
                label="reason"
                placeholder="Serve refund questions"
              />
              <.input field={@morph_form[:match]} label="exact match" placeholder="refund" />
              <.input field={@morph_form[:reply]} type="textarea" rows="5" label="reply template" />
              <div class="grid gap-4 sm:grid-cols-2">
                <.input field={@morph_form[:scopes]} label="scopes (comma separated)" />
                <.input field={@morph_form[:token_cap]} type="number" label="token cap" min="1" />
              </div>
              <.button variant="primary">create + evaluate proposal</.button>
            </.form>
          </.term_window>
        </div>
      </div>

      <div :if={@error || @result} class="mt-6">
        <.term_window title="bridge result" status={pending_label(@pending)}>
          <p :if={@error} class="term-out text-[0.75rem] t-fail">{@error}</p>
          <pre :if={@result} class="term-code overflow-auto">{@result}</pre>
        </.term_window>
      </div>
    </Layouts.app>
    """
  end

  @spec send_bridge(
          Phoenix.LiveView.Socket.t(),
          StudioBridge.operation(),
          Phoenix.HTML.Form.t(),
          (-> term())
        ) :: {:noreply, Phoenix.LiveView.Socket.t()}
  defp send_bridge(socket, operation, form, fun) do
    case fun.() do
      {:ok, envelope} ->
        pending = Map.put(socket.assigns.pending, envelope["id"], operation)

        {:noreply,
         socket
         |> assign(:morph_form, form)
         |> assign(pending: pending, error: nil, result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  @spec finish(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp finish(socket, request_id) do
    assign(socket, pending: Map.delete(socket.assigns.pending, request_id), error: nil)
  end

  @spec morph_form(map()) :: Phoenix.HTML.Form.t()
  defp morph_form(params \\ %{}) do
    to_form(
      %{
        "subject" => Map.get(params, "subject", ""),
        "action" => Map.get(params, "action", "mount"),
        "by" => Map.get(params, "by", "actor:studio"),
        "reason" => Map.get(params, "reason", ""),
        "mount_id" => Map.get(params, "mount_id", ""),
        "match" => Map.get(params, "match", ""),
        "reply" => Map.get(params, "reply", "{{input.text}}"),
        "scopes" => Map.get(params, "scopes", ""),
        "token_cap" => Map.get(params, "token_cap", "128")
      },
      as: :morph
    )
  end

  @spec required(map(), String.t()) :: {:ok, String.t()} | {:error, term()}
  defp required(params, key) do
    case params |> Map.get(key, "") |> String.trim() do
      "" -> {:error, {:required, key}}
      value -> {:ok, value}
    end
  end

  @spec comma_list(String.t() | nil) :: [String.t()]
  defp comma_list(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp comma_list(_value), do: []

  @spec positive_integer(String.t() | nil) :: pos_integer() | nil
  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> integer
      _invalid -> nil
    end
  end

  defp positive_integer(_value), do: nil

  @spec pending_label(map()) :: String.t()
  defp pending_label(pending) when map_size(pending) == 0, do: "complete"
  defp pending_label(pending), do: "#{map_size(pending)} pending"

  @spec describe(term()) :: String.t()
  defp describe({:required, field}), do: "#{field} is required"
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
