defmodule LoadBalancer do
  use GenServer

  @nr_of_workers 3

  def start_link do
    IO.puts "Starting load balancer..."
    state = Enum.reduce(1..@nr_of_workers, %{}, fn (i, acc) -> Map.put(acc, i, 0) end)
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def get_least_busy_worker do
    GenServer.call(__MODULE__, :get_least_busy_worker)
  end

  def handle_call(:get_least_busy_worker, _from, state) do
    id = state
    |> Enum.min_by(fn {_, v} -> v end)
    |> elem(0)

    state = Map.update(state, id, 1, &(&1 + 1))
    {:reply, id, state}
  end

  def release_worker(id) do
    GenServer.cast(__MODULE__, {:release, id})
  end

  def handle_cast({:release, id}, state) do
    state = Map.update(state, id, 0, &(&1 - 1))
    {:noreply, state}
  end

end
