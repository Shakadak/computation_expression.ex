defmodule ComputationExpressions do
  defmacro __using__(opts) do
    {debug?, []} = Keyword.pop(opts, :debug, false)
    quote do
      defmacro compute(do: {:__block__, _context, body}) do
        unquote(__MODULE__).build(__MODULE__, body, __CALLER__)
        |> case do x -> if unquote(debug?) do IO.puts(Macro.to_string(x)) end ; x end
      end
    end
  end

  def build(_module, [{:let!, context, _}], caller) do
    kind = CompileError
    opts = [
      file: caller.file,
      line: Keyword.get(context, :line, caller.line),
      description: "End of computation expression cannot be let!",
    ]
    raise kind, opts
  end

  def build(_module, [line], _caller) do
    line
  end

  def build(module, [{:let!, _ctxt, [{:=, _ctxt2, [binding, expression]}]} | tail], caller) do
    quote location: :keep do
      unquote(expression)
      |> unquote(module).bind(fn unquote(binding) ->
        unquote(build(module, tail, caller))
      end)
    end
  end

  def build(module, [{:=, _context, [_binding, _expression]} = line | tail], caller) do
    quote location: :keep do
      unquote(line)
      unquote(build(module, tail, caller))
    end
  end

  def build(module, [expression | tail], caller) do
    quote location: :keep do
      unquote(expression)
      |> unquote(module).bind(fn _ ->
        unquote(build(module, tail, caller))
      end)
    end
    #|> case do x -> IO.puts(Macro.to_string(x)) ; x end
  end
end
