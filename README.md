# FAF.PTR16.1 -- Project 1
> **Performed by:** Marcel Vlasenco, group FAF-203
> **Verified by:** asist. univ. Alexandru Osadcenco

## Description

This project is a simple implementation of a stream processing system. It consumes SSE events from a docker image.
```bash
$ docker run -p 4000:4000 alexburlacu/rtp-server:faf18x
```

## Supervision Tree Diagram
![Diagram](https://github.com/Marcel-MD/streamproc/blob/main/tree.png)

## Message Flow Diagram
![Diagram](https://github.com/Marcel-MD/streamproc/blob/main/message.png)

## Reader Actor
```elixir
defmodule Reader do
  use GenServer

  def start_link(url) do
    GenServer.start_link(__MODULE__, url: url)
  end

  def init([url: url]) do
    IO.puts "Connecting to stream..."
    HTTPoison.get!(url, [], [recv_timeout: :infinity, stream_to: self()])
    {:ok, nil}
  end

  def handle_info(%HTTPoison.AsyncChunk{chunk: chunk}, _state) do
    process_event(chunk)
    {:noreply, nil}
  end

    [...]

  defp process_event("event: \"message\"\n\ndata: " <> message) do
    {success, data} = Jason.decode(String.trim(message))

    if success == :ok do
      tweet = data["message"]["tweet"]
      text = tweet["text"]
      hashtags = tweet["entities"]["hashtags"]
      PrinterSuper.print(text)
      Enum.each(hashtags, fn hashtag -> Analyzer.analyze_hashtag(hashtag["text"]) end)
    end
  end

  defp process_event(_corrupted_event) do
    PrinterSuper.print(:kill)
  end
end
```

Reader actor is responsible for consuming the stream. It uses HTTPoison library to connect to the stream and receive events. It uses `stream_to: self()` option to receive events as messages. It then passes the event to `process_event/1` function. If the event is a message, it extracts the text and hashtags from it and sends them to the PrinterSuper and Analyzer actors respectively. If the event is corrupted, it sends a kill signal to the PrinterSuper actor.

## Reader Supervisor
```elixir
defmodule ReaderSuper do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
    |> elem(1)
  end

  def init([]) do
    children = [
      %{
        id: :reader1,
        start: {Reader, :start_link, ["http://localhost:4000/tweets/1"]}
      },
      %{
        id: :reader2,
        start: {Reader, :start_link, ["http://localhost:4000/tweets/2"]}
      },
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

Reader Supervisor starts the Reader actors. It passes the url for listening to server stream events.

## Printer Actor
```elixir
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
```

Printer actor is responsible for printing the messages. It receives messages from Printer Supervisor, after the message is printer it releases the resources from the Load Balancer to signal that it processed the message. If it receives a :kill signal, it releases the resources from the Load Balancer and stops.

## Printer Supervisor
```elixir
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
```

Printer Supervisor is responsible for starting the Printer actors and the Load Balancer. It also provides an interface for the Reader actor to interact with the Printer actors. It uses the Load Balancer to get the least busy Printer actor and sends the message to it.

## Load Balancer
```elixir
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
```

Load Balancer is responsible for keeping track of the number of messages each Printer actor is processing. It provides an interface for the Printer actors to signal that they are done processing a message and for the Printer Supervisor to get the least busy Printer actor.

## Analyzer Actor
```elixir
defmodule Analyzer do
  use GenServer

  @time 5

  def start_link do
    IO.puts "Starting analyzer..."
    GenServer.start_link(__MODULE__, {:os.timestamp(), %{}}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def analyze_hashtag(hashtag) do
    GenServer.cast(__MODULE__, hashtag)
  end

  def handle_cast(hashtag, state) do
    hashtags = state |> elem(1)
    hashtags = Map.update(hashtags, hashtag, 1, &(&1 + 1))

    start_time = state |> elem(0)
    end_time = :os.timestamp()
    elapsed = elapsed_seconds(start_time, end_time)

    if elapsed > @time do
      hashtags = hashtags |> Enum.sort_by(&elem(&1, 1), &>=/2) |> Enum.take(5)
      IO.puts "\nTop 5 hashtags in the last #{@time} seconds:"
      hashtags |> Enum.each(fn {hashtag, count} -> IO.puts "#{hashtag}: #{count}" end)
      {:noreply, {:os.timestamp(), %{}}}
    else
      {:noreply,{start_time, hashtags}}
    end
  end

  defp elapsed_seconds(start_time, end_time) do
    {_, sec, micro} = end_time
    {_, sec2, micro2} = start_time

    (sec - sec2) + (micro - micro2) / 1_000_000
  end
end
```

Analyzer actor is responsible for analyzing the hashtags. It keeps track of the number of times each hashtag appears in the last 5 seconds and prints the top 5 hashtags every 5 seconds. It uses the timestamp of the first message to calculate the elapsed time. It uses a map to keep track of the number of times each hashtag appears.