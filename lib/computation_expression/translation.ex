defmodule ComputationExpression.Translation do
  alias ComputationExpression.Translation.Auxiliary
  alias ComputationExpression.Parse

  import Auxiliary, only: [
    src: 2,
  ]
  import Parse

  def comp_expr(ast, builder_ast, b) do
    ast_ast = Enum.map(ast, &Parse.parse/1)
    #|> IO.inspect(label: "ast parsed")
    new_ast = translate_with_custom(ast_ast, builder_ast)

    check = if Module.open?(b) do
      &Module.defines?(b, {&1, &2}, :def)
    else
      &function_exported?(b, &1, &2)
    end

    new_ast = case check.(:_Delay, 1) do
      true -> quote do unquote(b)._Delay(fn -> unquote(new_ast) end) end
      false -> new_ast
    end
    new_ast = case check.(:_Quote, 1) do
      true -> b._Quote(new_ast)
      false -> new_ast
    end
    new_ast = case check.(:_Run, 1) do
      true -> quote do unquote(b)._Run(unquote(new_ast)) end
      false -> new_ast
    end
    new_ast
  end

  def expand(ast, b) do
    {env, _} = Code.eval_quoted(quote do require unquote(b) ; __ENV__ end)
    ast = Macro.expand(ast, env)
    ast
  end

  def translate_with_custom(cexpr_ast, b) do
    t(cexpr_ast, fn expr -> expr end, b)
  end

  def translate_basic(cexpr_ast, b) do
    t(cexpr_ast, fn expr -> expr end, b)
  end

  #def t([let(p, e) | [_|_] = ce], c, b) do
  #  t(ce, MapSet.union(var(p)), fn expr -> c.(quote do unquote(p) = unquote(e) ; unquote(expr) end) end, b)
  #end

  def t([let!(p, e) | [_|_] = ce], c, b) do
    next = fn ast ->
      ast = quote do unquote(b)._Bind(unquote(e), fn unquote(p) -> unquote(ast) end) end
      c.(ast)
    end
    t(ce, next, b)
  end

  def t([yield(e)], c, b) do
    c.(quote do unquote(b)._Yield(unquote(e)) end)
  end

  def t([yield!(e)], c, b) do
    c.(quote do unquote(b)._YieldFrom(unquote(e)) end)
  end

  def t([pure(e)], c, b) do
    ast = quote do unquote(b)._Pure(unquote(e)) end
    c.(ast)
  end

  def t([pure!(e)], c, b) do
    c.(quote do unquote(b)._PureFrom(unquote(e)) end)
  end

  def t([use_(p, e) | [_|_] = ce], c, b) do
    c.(quote do unquote(b)._Using(unquote(e), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end)
  end

  def t([use!(p, e) | [_|_] = ce], c, b) do
    c.(quote do unquote(b)._Bind(unquote(e), fn unquote(p) -> unquote(b)._Using(unquote(p), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end) end)
  end

  def t([match(val, cls)], c, b) do
    clauses = Enum.flat_map(cls, fn [pi, cei] ->
      quote do unquote(pi) -> unquote(translate_basic(cei, b)) end
    end)
    c.(quote do case unquote(val) do unquote_splicing(clauses) end end)
  end

  def t([match!(val, cls)], c, b) do
    var = Macro.unique_var(:x, __MODULE__)
    t([let!(var, val), match(var, cls)], c, b)
  end

  def t([while(cnd, ce)], c, b) do
    t(ce, fn expr -> c.(quote do unquote(b)._While(fn -> unquote(cnd) end, unquote(b)._Delay(fn -> unquote(expr) end)) end) end, b)
  end

  # try with

  # try finally

  def t([if_then(cnd, ce)], c, b) do
    t(ce, fn expr -> c.(quote do if unquote(cnd) do unquote(expr) else unquote(b)._Zero() end end) end, b)
  end

  def t([if_then_else(cnd, ce1, ce2)], c, b) do
    c.(quote do if unquote(cnd) do unquote(translate_basic(ce1, b)) else unquote(translate_basic(ce2, b)) end end)
  end

  # for to
  # for
  def t([for_(pat, expr, ce)], c, b) do
    next = fn ast ->
      ast = quote do
        unquote(b)._For(unquote(expr), fn unquote(pat) -> unquote(ast) end)
      end
      c.(ast)
    end
    t(ce, next, b)
  end

  def t([do_(e) | [_|_] = ce], c, b) do
    t(ce, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, b)
  end

  def t([do!(e) | [_|_] = ce], c, b) do
    unit = Macro.escape({})
    t([let!(unit, e) | ce], c, b)
  end

  # Must it always delay ?
  def t([cexpr(_, _) = ce1 | [_|_] = ce2], c, b) do
    c.(quote do unquote(b)._Combine(unquote(translate_basic([ce1], b)), unquote(b)._Delay(fn -> unquote(translate_basic(ce2, b)) end)) end)
  end

  def t([do!(e)], c, b) do
    unit = Macro.escape({})
    t([let!(unit, src(e, b)), pure(unit)], c, b)
  end

  def t([other_expr(e) | [_|_] = ce2], c, b) do
    t(ce2, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, b)
  end

  def t([other_expr(e)], c, b) do
    c.(quote do unquote(e) ; unquote(b)._Zero() end)
  end
end
