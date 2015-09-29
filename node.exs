defmodule Bully do
  @moduledoc """
  # Bully Algorithm

  Run algorithm with `iex --sname <id> node.exs`
  Then call `Bully.start` to start a single node
  or `Bully.connect <id>` to start and connect a node
  """

  @doc """
  Call this to start a node by itself
  """
  def start do
    # Start leader as itself
    init_leader Node.self
    start_monitoring
  end

  @doc """
  Call this to start a node and connect to an existing node
  """
  def connect(id, hostname \\ host) do
    remote = String.to_atom(to_string(id) <> "@" <> hostname)
    # Connect to other nodes
    Node.connect remote
    # Get current leader
    init_leader rpc(remote, :leader)
    start_election
    start_monitoring
  end

  @doc """
  Get current leader
  """
  def current_leader do
    Agent.get(:leader, &(&1))
  end

  @doc """
  Update current leader
  """
  def update_leader(new_leader) do
    Agent.update(:leader, fn(_) -> new_leader end)
  end

  defp host do
    :inet.gethostname()
    |> elem(1)
    |> to_string
  end

  defp init_leader(leader) do
    Agent.start_link(fn -> leader end, name: :leader)
  end

  defp start_monitoring do
    # Get nodes status messages
    :global_group.monitor_nodes(true)
    loop
  end

  defp start_election do
    IO.puts "ELECTION!"

    if higher_nodes? do
      IO.puts "Lost election :("
    else
      IO.puts "Won election \\o/"
      update_leader Node.self
      broadcast_victory
    end
  end

  defp higher_nodes? do
    Node.list
    # Get all nodes higher than itself
    |> Enum.filter(fn(node) -> node > Node.self end)
    # Test if any is alive
    |> Enum.any?(fn(node) -> Node.ping(node) == :pong end)
  end

  defp broadcast_victory do
    Node.list
    |> Enum.each(fn(node) -> rpc(node, :update_leader, [Node.self]) end)
  end

  defp loop do
    receive do
      {:nodeup, node} ->
        IO.puts "Node connected: " <> to_string(node)
        start_election
      {:nodedown, node} ->
        IO.puts "Node disconnected: " <> to_string(node)
        if node == current_leader, do: start_election
    after
      1000 ->
        IO.puts "Current leader: " <> to_string(current_leader)
    end
    loop
  end

  defp rpc(remote, method, args \\ []) do
    :rpc.call(remote, __MODULE__, method, args, 5000)
  end
end
