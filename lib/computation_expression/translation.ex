defmodule ComputationExpression.Translation do
  alias ComputationExpression.Parse
  import Parse

  def comp_expr(ast, builder_ast, b, usage, _debug?) do
    ast_ast = Enum.map(ast, &Parse.parse/1)
    #case debug? do
    #  true -> IO.inspect(ast_ast, label: "ast parsed")
    #  false -> {}
    #end

    invoke = case usage do
      :self -> fn ast -> ast end
      :outside -> fn ast -> quote do unquote(builder_ast).unquote(ast) end end
    end
    new_ast = translate_basic(ast_ast, invoke)

    check = if Module.open?(b) do
      &Module.defines?(b, {&1, &2}, :def)
    else
      &function_exported?(b, &1, &2) or macro_exported?(b, &1, &2)
    end

    new_ast = case check.(:_Delay, 1) do
      true -> invoke.(quote do _Delay(fn -> unquote(new_ast) end) end)
      false -> new_ast
    end
    new_ast = case check.(:_Quote, 1) do
      true -> b._Quote(new_ast)
      false -> new_ast
    end
    new_ast = case check.(:_Run, 1) do
      true -> invoke.(quote do _Run(unquote(new_ast)) end)
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

  def t([let(e) | [_|_] = ce], c, b) do
    t(ce, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, b)
  end

  def t([let!(p, e, ctxt) | [_|_] = ce], c, b) do
    ctxt = Map.new(ctxt)
    next = fn ast ->
      fn_ast = quote line: ctxt.line do fn unquote(p) -> unquote(ast) end end
      ast = quote do _Bind(unquote(e), unquote(fn_ast)) end
      c.(b.(ast))
    end
    t(ce, next, b)
  end

  def t([yield(e)], c, b) do
    ast = quote do _Yield(unquote(e)) end
    c.(b.(ast))
  end

  def t([yield!(e)], c, b) do
    ast = quote do _YieldFrom(unquote(e)) end
    c.(b.(ast))
  end

  def t([pure(e)], c, b) do
    ast = quote do _Pure(unquote(e)) end
    c.(b.(ast))
  end

  def t([pure!(e)], c, b) do
    ast = b.(quote do _PureFrom(unquote(e)) end)
    c.(ast)
  end

  def t([use_(p, e) | [_|_] = ce], c, b) do
    ast = quote do _Using(unquote(e), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end
    c.(b.(ast))
  end

  def t([use!(p, e) | [_|_] = ce], c, b) do
    inner_ast = quote do _Using(unquote(p), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end
    inner_ast = b.(inner_ast)
    ast = quote do _Bind(unquote(e), fn unquote(p) -> unquote(inner_ast) end) end
    c.(b.(ast))
  end

  def t([match(val, cls, ctxt)], c, b) do
    clauses = Enum.flat_map(cls, fn {pi, cei, ctxt} ->
      quote line: Keyword.fetch!(ctxt, :line) do unquote(pi) -> unquote(translate_basic(cei, b)) end
    end)
    line = Keyword.fetch!(ctxt, :line)
    c.(quote line: line do case unquote(val) do unquote(clauses) end end)
  end

  def t([match!(val, cls, ctxt)], c, b) do
    var = Macro.unique_var(:x, __MODULE__)
    t([let!(var, val, ctxt), match(var, cls, ctxt)], c, b)
  end

  def t([while(cnd, ce)], c, b) do
    t(ce, fn expr ->
      inner_ast = b.(quote do _Delay(fn -> unquote(expr) end) end)
      ast = quote do _While(fn -> unquote(cnd) end, unquote(inner_ast)) end
      c.(b.(ast))
    end, b)
  end

  # try with

  # try finally

  def t([if_then(cnd, ce)], c, b) do
    t(ce, fn expr ->
      ast = b.(quote do _Zero() end)
      c.(quote do if unquote(cnd) do unquote(expr) else unquote(ast) end end)
      end, b)
  end

  # def t([if_then(cnd, ce) | [_|_] = ce], c, b) do
  #   e = t(ce, fn expr -> c.(quote do if unquote(cnd) do unquote(expr) else unquote(b)._Zero() end end) end, b)
  #   t([do!(e) | ce], c, b)
  # end

  def t([if_then_else(cnd, ce1, ce2)], c, b) do
    c.(quote do if unquote(cnd) do unquote(translate_basic(ce1, b)) else unquote(translate_basic(ce2, b)) end end)
  end

  # for to
  # for
  def t([for_(pat, expr, ce)], c, b) do
    next = fn ast ->
      ast = b.(quote do
        _For(unquote(expr), fn unquote(pat) -> unquote(ast) end)
      end)
      c.(ast)
    end
    t(ce, next, b)
  end

  def t([do_(e) | [_|_] = ce], c, b) do
    t(ce, fn expr -> c.(quote do unquote(gen_other(e)) ; unquote(expr) end) end, b)
  end

  def t([do!(e) | [_|_] = ce], c, b) do
    {_, ctxt, _} = e
    unit = Macro.escape({})
    t([let!(unit, e, ctxt) | ce], c, b)
  end

  # Must it always delay ?
  def t([cexpr(_, _) = ce1 | [_|_] = ce2], c, b) do
    inner_ast = quote do _Delay(fn -> unquote(translate_basic(ce2, b)) end) end
    ast = b.(quote do _Combine(unquote(translate_basic([ce1], b)), unquote(inner_ast)) end)
    c.(ast)
  end

  def t([do!(e)], c, b) do
    {_, ctxt, _} = e
    unit = Macro.escape({})
    t([let!(unit, e, ctxt), pure(unit)], c, b)
  end

  def t([other_expr(e) | [_|_] = ce2], c, b) do
    t(ce2, fn expr -> c.(quote do unquote(gen_other(e)) ; unquote(expr) end) end, b)
  end

  def t([other_expr(e)], c, b) do
    ast = b.(quote do _Zero() end)
    c.(quote do unquote(gen_other(e)) ; unquote(ast) end)
  end

  def gen_other(e) do
    meta = case e do
      {_, meta, _} -> meta
      _ -> []
    end

    {l, meta2, r} = quote do {} = unquote(e) end
    other = {l, meta ++ meta2, r}
    other
  end
end
