defmodule ComputationExpression.Translation.Auxiliary do
  def var(ast) do
    Macro.postwalker(ast)
    |> Enum.filter(fn
      {_name, _meta, ctxt} when is_atom(ctxt) -> true
      _ -> false
    end)
    |> MapSet.new()
  end

  def src(ast, _b) do
    ast
  end

  def assert(true), do: {}
end
