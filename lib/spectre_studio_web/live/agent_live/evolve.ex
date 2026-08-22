defmodule SpectreStudioWeb.AgentLive.Evolve do
  @moduledoc """
  Per-Agent runtime Skill creation and governed Morph proposal authoring.

  Direct Skill mounts and Morph proposals are deliberately separate actions.
  A Morph request creates and evaluates a candidate; it never implies approval
  or activation, which remain independent host commits.
  """

  use SpectreStudioWeb, :live_view

  import SpectreStudioWeb.AgentLive.Shell

  alias SpectreStudio.Pulse.Scopes
  alias SpectreStudio.Pulse.StudioBridge
  alias SpectreStudioWeb.AgentLive.Shell

  @requirements {:any, [:skill_create, :morph_create]}

  @impl Phoenix.LiveView
  def mount(params, _session, socket) do
    case Shell.mount_agent(socket, params, :evolve, @requirements) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(:pending, %{})
         |> assign(:error, nil)
         |> assign(:result, nil)
         |> assign(:skill_form, skill_form())
         |> assign(:morph_form, morph_form())}

      {:redirect, socket} ->
        {:ok, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("mount-skill", %{"skill" => params}, socket) do
    with {:ok, definition} <- decode_object(params["definition"]),
         {:ok, subject} <- required(params, "subject"),
         {:ok, mount_id} <- required(params, "mount_id") do
      attrs = %{
        "subject" => subject,
        "mount_id" => mount_id,
        "definition" => definition
      }

      send_bridge(socket, :skill_mount, skill_form(params), fn ->
        StudioBridge.mount_skill(
          socket.assigns.connection.id,
          socket.assigns.agent.address,
          attrs
        )
      end)
    else
      {:error, reason} -> {:noreply, assign(socket, :error, describe(reason))}
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
  def handle_info({:envelope, _connection_id, envelope}, socket) do
    case StudioBridge.response(envelope, socket.assigns.pending) do
      {:ok, request_id, operation, data} when operation in [:skill_mount, :morph_propose] ->
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
      |> assign(:can_mount_skill?, Scopes.can?(assigns.connection.manifest, :skill_create))
      |> assign(:can_propose_morph?, Scopes.can?(assigns.connection.manifest, :morph_create))

    ~H"""
    <Layouts.app
      flash={@flash}
      connections={@connections}
      active_section={@active_section}
      active_connection={@active_connection}
    >
      <.agent_header connection={@connection} agent={@agent} tab={@tab} />

      <div class="mt-6 grid gap-6 xl:grid-cols-2">
        <.term_window :if={@can_mount_skill?} title="mount runtime Skill" status="host-governed">
          <p class="mb-5 text-[0.75rem] leading-6 t-dim">
            The host must build a <span class="t-strong">Spectre.Skill.Definition</span>,
            apply its Authority Envelope and mount it with revision fencing.
          </p>

          <.form for={@skill_form} id="skill-form" phx-submit="mount-skill" class="space-y-4">
            <div class="grid gap-4 sm:grid-cols-2">
              <.input field={@skill_form[:subject]} label="subject" placeholder="account-123" />
              <.input field={@skill_form[:mount_id]} label="mount id" placeholder="refunds" />
            </div>
            <.input
              field={@skill_form[:definition]}
              type="textarea"
              rows="18"
              label="runtime Skill definition (JSON)"
            />
            <.button variant="primary">create + mount Skill</.button>
          </.form>
        </.term_window>

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
            <.input field={@morph_form[:reason]} label="reason" placeholder="Serve refund questions" />
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
        form_key = if operation == :skill_mount, do: :skill_form, else: :morph_form

        {:noreply,
         socket
         |> assign(form_key, form)
         |> assign(pending: pending, error: nil, result: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, describe(reason))}
    end
  end

  @spec finish(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  defp finish(socket, request_id) do
    assign(socket, pending: Map.delete(socket.assigns.pending, request_id), error: nil)
  end

  @spec skill_form(map()) :: Phoenix.HTML.Form.t()
  defp skill_form(params \\ %{}) do
    to_form(
      %{
        "subject" => Map.get(params, "subject", ""),
        "mount_id" => Map.get(params, "mount_id", ""),
        "definition" => Map.get(params, "definition", default_skill_definition())
      },
      as: :skill
    )
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

  @spec default_skill_definition() :: String.t()
  defp default_skill_definition do
    Jason.encode!(
      %{
        "id" => "new-skill",
        "declared_version" => 1,
        "publisher_ref" => "spectre.studio",
        "applicability" => %{"scopes" => ["default"], "positive" => [], "negative" => []},
        "prompt_budget" => 128,
        "prompt_fragments" => [],
        "flows" => []
      },
      pretty: true
    )
  end

  @spec decode_object(String.t() | nil) :: {:ok, map()} | {:error, atom()}
  defp decode_object(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _other} -> {:error, :definition_must_be_an_object}
      {:error, _reason} -> {:error, :invalid_definition_json}
    end
  end

  defp decode_object(_value), do: {:error, :invalid_definition_json}

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
  defp describe(:invalid_definition_json), do: "Skill definition is not valid JSON"
  defp describe(:definition_must_be_an_object), do: "Skill definition must be a JSON object"
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
