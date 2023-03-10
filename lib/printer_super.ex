defmodule PrinterSuper do
  use Supervisor

  @nr_of_workers 3

  def start_link do
    pid = Supervisor.start_link(__MODULE__, nr_of_workers: @nr_of_workers, name: __MODULE__)
    |> elem(1)
    Process.register(pid, __MODULE__)
  end

  def init(args) do
    children = Enum.map(1..args[:nr_of_workers], fn i ->
      %{
        id: i,
        start: {Printer, :start_link, [i]}
      }
    end)

    children = children ++ [
      %{
        id: :load_balancer,
        start: {LoadBalancer, :start_link, []}
      },
      %{
        id: :analyzer,
        start: {Analyzer, :start_link, []}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def print(msg) do
    id = LoadBalancer.get_least_busy_worker()
    pid = get_worker_pid(id)
    Printer.print(pid, msg)
  end

  def get_worker_pid(id) do
    Supervisor.which_children(__MODULE__)
    |> Enum.find(fn {i, _, _, _} -> i == id end)
    |> elem(1)
  end

  def count() do
    Supervisor.count_children(__MODULE__)
  end
end
