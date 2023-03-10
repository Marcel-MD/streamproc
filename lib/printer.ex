defmodule Printer do
  use GenServer

  @min_sleep_time 5
  @max_sleep_time 50

  def start_link(id) do
    IO.puts "Starting printer #{id}..."
    GenServer.start_link(__MODULE__, id)
  end

  def init(state) do
    {:ok, state}
  end

  def print(pid, msg) do
    GenServer.cast(pid, msg)
  end

  def handle_cast(:kill, state) do
    IO.puts("## Killing printer ##")
    LoadBalancer.release_worker(state)
    {:stop, :normal, state}
  end

  def handle_cast(msg, state) do
    sleep_randomly()
    IO.puts "\n#{inspect msg}"
    LoadBalancer.release_worker(state)
    {:noreply, state}
  end

  defp sleep_randomly do
    sleep_time = :rand.uniform(@max_sleep_time - @min_sleep_time) + @min_sleep_time
    Process.sleep(sleep_time)
  end
end
