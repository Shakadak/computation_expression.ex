defmodule Test.List do
  use ComputationExpressions, debug: true

  def bind(m, f) do
    m |> Enum.flat_map(f)
  end

  def zero() do
    _ = IO.puts("Zero")
    []
  end

  def return(x) do
    _ = IO.puts("Return an unwrapped #{inspect(x)} as a list")
    [x]
  end

  def yield(x) do
    _ = IO.puts("Return an unwrapped #{inspect(x)} as a list")
    [x]
  end

  def yield_from(m) do
    _ = IO.puts("Yield a list (#{inspect(m)}) directly")
    m
  end

  def for(m, f) do
    _ = IO.puts("For #{inspect(m)}")
    bind(m, f)
  end

  def combine(a, b) do
    _ = IO.puts("combining #{inspect(a)} and #{inspect(b)}")
    Enum.concat(a, b)
  end

  def delay(f) do
    _ = IO.puts("Delay")
    f.()
  end
end
