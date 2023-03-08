defmodule Printer do
  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [])
  end

  def init(state) do
    {:ok, state}
  end

  def print(pid, msg) do
    GenServer.cast(pid, msg)
  end

  def handle_cast(msg, state) do
    IO.puts "\n#{inspect msg}"
    {:noreply, state}
  end
end
