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

    "event: \"message\"\n\ndata: " <> message = chunk
    {success, data} = Jason.decode(String.trim(message))

    if success == :ok do
      message = data["message"]
      tweet = message["tweet"]
      text = tweet["text"]
      PrinterSuper.print(text)
    end

    {:noreply, nil}
  end

  # In addition to message chunks, we also may receive status changes etc.
  def handle_info(%HTTPoison.AsyncStatus{} = status, _state) do
    IO.puts "Connection status: #{inspect status}"
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncHeaders{} = headers, _state) do
    IO.puts "Connection headers: #{inspect headers}"
    {:noreply, nil}
  end

  def handle_info(%HTTPoison.AsyncEnd{} = connection_end, _state) do
    IO.puts "Connection end: #{inspect connection_end}"
    {:noreply, nil}
  end
end
