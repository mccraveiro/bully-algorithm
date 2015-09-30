defmodule Bully do
  @moduledoc """
  # Bully Algorithm

  Run algorithm with `iex --sname <id> node.exs`
  Then call `Bully.start` to start a single node
  or `Bully.connect <id>` to start and connect a node
  """

  defp init do
    # Start leader as itself
    init_leader Node.self
    # Get nodes status messages
    :global_group.monitor_nodes(true)
    :global.register_name Node.self, self
  end

  @doc """
  Call this to start a node by itself
  """
  def start do
    init
    loop
  end

  @doc """
  Call this to start a node and connect to an existing node
  """
  def connect(id, hostname \\ host) do
    init
    # Connect to other nodes
    Node.connect(String.to_atom(to_string(id) <> "@" <> hostname))
    :global.sync
    loop
  end

  defp init_leader(leader) do
    Agent.start_link(fn -> leader end, name: :leader)
  end

  defp current_leader do
    Agent.get(:leader, &(&1))
  end

  defp update_leader(new_leader) do
    Agent.update(:leader, fn(_) -> new_leader end)
  end

  defp host do
    # Get localhost name
    :inet.gethostname()
    |> elem(1)
    |> to_string
  end

  defp start_election do
    IO.puts "ELECTION!"

    if any_higher_nodes? do
      IO.puts "Lost election :("
      # wait 5s if no coordinator, start election again
      receive do
        {:coordinator, node} -> update_leader(node)
      after
        5_000 -> start_election
      end
    else
      IO.puts "Won election \\o/"
      update_leader Node.self
      broadcast_victory
    end
  end

  defp any_higher_nodes? do
    Node.list
    # Get all nodes higher than itself
    |> Enum.filter(fn(node) -> node > Node.self end)
    # Test if any is alive
    |> Enum.any?(fn(node) ->
      :global.send node, {:election, Node.self}

      receive do
        {:alive, remote} when remote == node -> true
      after
        5_000 -> false
      end
    end)
  end

  defp broadcast_victory do
    # Send a coordinator message for each node
    Enum.each(Node.list, fn(node) ->
      :global.send node, {:coordinator, Node.self}
    end)
  end

  defp on(:nodeup, node) do
    IO.puts "Node connected: " <> to_string(node)
    :global.sync

    if node > current_leader do
      start_election
    end
  end

  defp on(:nodedown, node) do
    IO.puts "Node disconnected: " <> to_string(node)

    if node == current_leader do
      start_election
    end
  end

  defp on(:election, node) do
    :global.send node, {:alive, Node.self}

    if Node.self > node do
      start_election
    end
  end

  defp on(:coordinator, node) do
    if Node.self > node do
      start_election
    else
      update_leader node
    end
  end

  defp loop do
    receive do
      {event, node} -> on(event, node)
    after
      1000 -> IO.puts("Current leader: " <> to_string(current_leader))
    end

    loop
  end
end
