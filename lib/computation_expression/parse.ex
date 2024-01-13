defmodule ComputationExpression.Parse do

  defmacro other_expr(expr), do: {:other_expr, expr}
  defmacro cexpr(op, expr), do: quote(do: {:cexpr, unquote(op), unquote(expr)})

  defmacro let!(pat, expr), do: quote(do: {:cexpr, :let!, [unquote(pat), unquote(expr)]})
  defmacro yield(expr), do: quote(do: {:cexpr, :yield, unquote(expr)})
  defmacro yield!(expr), do: quote(do: {:cexpr, :yield!, unquote(expr)})
  defmacro pure(expr), do: quote(do: {:cexpr, :pure, unquote(expr)})
  defmacro pure!(expr), do: quote(do: {:cexpr, :pure!, unquote(expr)})
  defmacro use_(pat, expr), do: quote(do: {:cexpr, :use_, [unquote(pat), unquote(expr)]})
  defmacro use!(pat, expr), do: quote(do: {:cexpr, :use!, [unquote(pat), unquote(expr)]})
  defmacro match(val, clauses), do: quote(do: {:cexpr, :match, [unquote(val), unquote(clauses)]})
  defmacro match!(val, clauses), do: quote(do: {:cexpr, :match!, [unquote(val), unquote(clauses)]})
  defmacro while(cnd, expr), do: quote(do: {:cexpr, :while, [unquote(cnd), unquote(expr)]})
  defmacro if_then(cnd, then), do: quote(do: {:cexpr, :if_then, [unquote(cnd), unquote(then)]})
  defmacro if_then_else(cnd, then, else_), do: quote(do: {:cexpr, :if_then_else, [unquote(cnd), unquote(then), unquote(else_)]})
  defmacro do_(expr), do: quote(do: {:cexpr, :do_, [unquote(expr)]})
  defmacro do!(expr), do: quote(do: {:cexpr, :do!, [unquote(expr)]})

  def parse({:let, _ctxt, [{:=, _ctxt2, [_p, _e]} = expr]}) do
    other_expr(expr)
  end

  def parse({:let!, _ctxt, [{:=, _ctxt2, [p, e]}]}) do
    let!(p, e)
  end

  def parse({:yield, _ctxt, [e]}) do
    yield(e)
  end

  def parse({:yield!, _ctxt, [e]}) do
    yield!(e)
  end

  def parse({:pure, _ctxt, [e]}) do
    pure(e)
  end

  def parse({:pure!, _ctxt, [e]}) do
    pure!(e)
  end

  def parse({:use_, _ctxt, [{:=, _ctxt2, [p, e]}]}) do
    use_(p, e)
  end

  def parse({:use!, _ctxt, [{:=, _ctxt2, [p, e]}]}) do
    use!(p, e)
  end

  def parse({:match, _ctxt, [val, do: cls]}) do
    clauses = Enum.map(cls, fn {:->, _, [[pi], cei]} ->
      ncei =
        ComputationExpression.normalize_body(cei)
        |> Enum.map(&parse/1)
      [pi, ncei]
    end)
    match(val, clauses)
  end

  def parse({:match!, _ctxt, [val, do: cls]}) do
    clauses = Enum.map(cls, fn {:->, _, [[pi], cei]} ->
      ncei =
        ComputationExpression.normalize_body(cei)
        |> Enum.map(&parse/1)
      [pi, ncei]
    end)
    match!(val, clauses)
  end

  def parse({:while, _ctxt, [cnd, do: ce]}) do
    nce =
      ComputationExpression.normalize_body(ce)
      |> Enum.map(&parse/1)
    while(cnd, nce)
  end

  # try with

  # try finally

  def parse({:if, _ctxt, [cnd, do: ce]}) do
    nce =
      ComputationExpression.normalize_body(ce)
      |> Enum.map(&parse/1)
    if_then(cnd, nce)
  end

  def parse({:if, _ctxt, [cnd, do: ce1, else: ce2]}) do
    nce1 =
      ComputationExpression.normalize_body(ce1)
      |> Enum.map(&parse/1)
    nce2 =
      ComputationExpression.normalize_body(ce2)
      |> Enum.map(&parse/1)
    if_then_else(cnd, nce1, nce2)
  end

  # for to
  # for joinOp
  # for groupJoinOp
  # for

  def parse({:do_, _ctx, [e]}) do
    do_(e)
  end

  def parse({:do!, _ctx, [e]}) do
    do!(e)
  end

  # joinOp
  # groupJoinOp
  # customOperator
  # customOperator(maintainsVarSpaceUsingBind) ; e
  # customOperator ; e

  def parse(other) do
    other_expr(other)
  end
end
