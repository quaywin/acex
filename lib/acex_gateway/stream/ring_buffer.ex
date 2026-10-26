defmodule AcexGateway.Stream.RingBuffer do
  @moduledoc """
  A memory-efficient Circular Ring Buffer for MPEG-TS chunks.
  Maintains the most recent `max_bytes` of video data so newly connected clients
  can immediately receive a keyframe/PAT/PMT sequence and start playing without black screens.
  """

  defstruct chunks: :queue.new(),
            total_bytes: 0,
            # 2MB default (~2-3 seconds of 1080p stream)
            max_bytes: 2_097_152

  @type t :: %__MODULE__{
          chunks: :queue.queue(binary()),
          total_bytes: non_neg_integer(),
          max_bytes: pos_integer()
        }

  @doc """
  Creates a new RingBuffer with a given max size in bytes.
  """
  def new(max_bytes \\ 2_097_152) when is_integer(max_bytes) and max_bytes > 0 do
    %__MODULE__{chunks: :queue.new(), total_bytes: 0, max_bytes: max_bytes}
  end

  @doc """
  Pushes a new binary chunk into the buffer. Drops oldest chunks if capacity is exceeded.
  """
  def push(%__MODULE__{} = buffer, chunk) when is_binary(chunk) do
    chunk_size = byte_size(chunk)
    new_queue = :queue.in(chunk, buffer.chunks)
    new_total = buffer.total_bytes + chunk_size

    trim(%{buffer | chunks: new_queue, total_bytes: new_total})
  end

  @doc """
  Returns all buffered chunks in chronological order.
  """
  def to_chunks(%__MODULE__{chunks: queue}) do
    :queue.to_list(queue)
  end

  @doc """
  Clears the ring buffer.
  """
  def clear(%__MODULE__{} = buffer) do
    %{buffer | chunks: :queue.new(), total_bytes: 0}
  end

  # Internal trimming to stay within max_bytes
  defp trim(%__MODULE__{total_bytes: total, max_bytes: max} = buffer) when total > max do
    case :queue.out(buffer.chunks) do
      {{:value, oldest_chunk}, remaining_queue} ->
        remaining_total = total - byte_size(oldest_chunk)
        trim(%{buffer | chunks: remaining_queue, total_bytes: remaining_total})

      {:empty, _} ->
        %{buffer | total_bytes: 0}
    end
  end

  defp trim(buffer), do: buffer
end
