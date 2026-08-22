defmodule SpectreStudio.Pulse.Events do
  @moduledoc """
  PubSub topics for connection activity.

  LiveViews never talk to a socket. They subscribe here and receive what the
  connection process decided to publish, which keeps one owner for connection
  state no matter how many browser tabs are watching it.
  """

  @pubsub SpectreStudio.PubSub

  @doc "Topic carrying the set of configured connections."
  @spec directory_topic() :: String.t()
  def directory_topic, do: "studio:connections"

  @doc "Topic carrying everything about one connection."
  @spec connection_topic(String.t()) :: String.t()
  def connection_topic(id), do: "studio:connection:" <> id

  @doc "Subscribes the calling process to a topic."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  @doc "Unsubscribes the calling process from a topic."
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: Phoenix.PubSub.unsubscribe(@pubsub, topic)

  @doc false
  @spec broadcast(String.t(), term()) :: :ok
  def broadcast(topic, message), do: Phoenix.PubSub.broadcast(@pubsub, topic, message)

  @doc false
  @spec directory_changed() :: :ok
  def directory_changed, do: broadcast(directory_topic(), :directory_changed)
end
