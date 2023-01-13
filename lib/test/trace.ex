defmodule Test.Option do
  defmacro some(x), do: {:some, x}
  defmacro none, do: :none

  def bind(none(), _), do: none()
  def bind(some(x), f), do: f.(x)
end

defmodule Test.Trace do
  use ComputationExpressions, debug: true

  import Test.Option, only: [
    some: 1,
    none: 0,
  ]

  def bind(m, f) do
    _ = case m do
      none() ->
        IO.puts("Binding with None. Exiting.")
      some(a) ->
        IO.puts("Binding with Some(#{inspect(a)}). Continuing.")
    end
    Test.Option.bind(m, f)
  end

  def return(x) do
    _ = IO.puts("Returning an unwrapped #{inspect(x)} as an Option.")
    some(x)
  end

  def return_from(x) do
    _ = IO.puts("Return an option (#{inspect(x)}) directly.")
    x
  end

  def zero do
    _ = IO.puts("Zero.")
    none()
  end

  def yield(x) do
    _ = IO.puts("Yield an unwrapped #{inspect(x)} as an option.")
    some(x)
  end

  def yield_from(x) do
    _ = IO.puts("Yield an option #{inspect(x)} directly.")
    some(x)
  end

  def combine(a, b) do
    case {a, b} do
      {some(a), some(b)} ->
        _ = IO.puts("combining #{inspect(a)} and #{inspect(b)}")
        some(a + b)
      {some(a), none()} ->
        _ = IO.puts("combining #{inspect(a)} and None")
        some(a)
      {none(), some(b)} ->
        _ = IO.puts("combining None and #{inspect(b)}")
        some(b)
      {none(), none()} ->
        _ = IO.puts("combining None with None")
        none()
    end
  end

  def delay(f) do
    _ = IO.puts("Delay")
    f.()
  end
end
