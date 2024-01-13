defmodule ComputationExpression.Translation do
  alias ComputationExpression.Translation.Auxiliary
  alias ComputationExpression.Parse

  import Auxiliary, only: [
    var: 1,
    src: 2,
    assert: 1,
  ]
  import Parse

  def comp_expr(ast, builder_ast, b) do
    ast_ast = Enum.map(ast, &Parse.parse/1)
    new_ast = translate_with_custom(ast_ast, builder_ast)
    if Module.open?(b) do
      new_ast = case Module.defines?(b, {:_Delay, 1}, :def) do
        true -> quote do unquote(b).delay(fn -> unquote(new_ast) end) end
        false -> new_ast
      end
      new_ast = case Module.defines?(b, {:_Quote, 1}, :def) do
        true -> b._Quote(new_ast)
        false -> new_ast
      end
      new_ast = case Module.defines?(b, {:_Run, 1}, :def) do
        true -> quote do unquote(b)._Run(unquote(new_ast)) end
        false -> new_ast
      end
      new_ast
    else
      new_ast = case function_exported?(b, :_Delay, 1) do
        true -> quote do unquote(b).delay(fn -> unquote(new_ast) end) end
        false -> new_ast
      end
      new_ast = case function_exported?(b, :_Quote, 1) do
        true -> b._Quote(new_ast)
        false -> new_ast
      end
      new_ast = case function_exported?(b, :_Run, 1) do
        true -> quote do unquote(b)._Run(unquote(new_ast)) end
        false -> new_ast
      end
      new_ast
    end
  end

  def translate_with_custom(cexpr_ast, b) do
    t(cexpr_ast, MapSet.new(), fn expr -> expr end, true, b)
  end

  def translate_basic(cexpr_ast, b) do
    t(cexpr_ast, MapSet.new(), fn expr -> expr end, false, b)
  end

  #def t([let(p, e) | [_|_] = ce], v, c, q, b) do
  #  t(ce, MapSet.union(v, var(p)), fn expr -> c.(quote do unquote(p) = unquote(e) ; unquote(expr) end) end, q, b)
  #end

  def t([let!(p, e) | [_|_] = ce], v, c, q, b) do
    next = fn expr ->
      ast = quote do unquote(b)._Bind(unquote(src(e, b)), fn unquote(p) -> unquote(expr) end) end
      # {env, _} = Code.eval_quoted(quote do require unquote(b) ; __ENV__ end)
      # ast = Macro.expand(ast, env)
      c.(ast)
    end
    t(ce, MapSet.union(v, var(p)), next, q, b)
  end

  def t([yield(e)], _v, c, _q, b) do
    c.(quote do unquote(b)._Yield(unquote(e)) end)
  end

  def t([yield!(e)], _v, c, _q, b) do
    c.(quote do unquote(b)._YieldFrom(unquote(e)) end)
  end

  def t([pure(e)], _v, c, _q, b) do
    ast = quote do unquote(b)._Pure(unquote(e)) end
    # {env, _} = Code.eval_quoted(quote do require unquote(b) ; __ENV__ end)
    # ast = Macro.expand(ast, env)
    c.(ast)
  end

  def t([pure!(e)], _v, c, _q, b) do
    c.(quote do unquote(b)._PureFrom(unquote(e)) end)
  end

  def t([use_(p, e) | [_|_] = ce], _v, c, _q, b) do
    c.(quote do unquote(b)._Using(unquote(e), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end)
  end

  def t([use!(p, e) | [_|_] = ce], _v, c, _q, b) do
    c.(quote do unquote(b)._Bind(unquote(src(e, b)), fn unquote(p) -> unquote(b)._Using(unquote(p), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end) end)
  end

  def t([match(val, cls)], _v, c, _q, b) do
    clauses = Enum.flat_map(cls, fn [pi, cei] ->
      quote do unquote(pi) -> unquote(translate_basic(cei, b)) end
    end)
    c.(quote do case unquote(val) do unquote_splicing(clauses) end end)
  end

  def t([match!(val, cls)], v, c, q, b) do
    var = Macro.unique_var(:x, __MODULE__)
    t([let!(var, val), match(var, cls)], v, c, q, b)
  end

  def t([while(cnd, ce)], v, c, q, b) do
    t(ce, v, fn expr -> c.(quote do unquote(b)._While(fn -> unquote(cnd) end, unquote(b)._Delay(fn -> unquote(expr) end)) end) end, q, b)
  end

  # try with

  # try finally

  def t([if_then(cnd, ce)], v, c, q, b) do
    t(ce, v, fn expr -> c.(quote do if unquote(cnd) do unquote(expr) else unquote(b)._Zero() end end) end, q, b)
  end

  def t([if_then_else(cnd, ce1, ce2)], _v, c, q, b) do
    assert(not q)
    c.(quote do if unquote(cnd) do unquote(translate_basic(ce1, b)) else unquote(translate_basic(ce2, b)) end end)
  end

  # for to
  # for joinOp
  # for groupJoinOp
  # for

  def t([do_(e) | [_|_] = ce], v, c, q, b) do
    t(ce, v, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, q, b)
  end

  def t([do!(e) | [_|_] = ce], v, c, q, b) do
    unit = Macro.escape({})
    t([let!(unit, e), ce], v, c, q, b)
  end

  # joinOp
  # groupJoinOp
  # customOperator
  # customOperator(maintainsVarSpaceUsingBind) ; e
  # customOperator ; e

  # Must it always delay ?
  def t([cexpr(_, _) = ce1 | [_|_] = ce2], _v, c, _q, b) do
    c.(quote do unquote(b)._Combine(unquote(translate_basic([ce1], b)), unquote(b)._Delay(fn -> unquote(translate_basic(ce2, b)) end)) end)
  end

  def t([do!(e)], v, c, q, b) do
    unit = Macro.escape({})
    t([let!(unit, src(e, b)), pure(unit)], v, c, q, b)
  end

  def t([other_expr(e) | [_|_] = ce2], v, c, q, b) do
    t(ce2, v, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, q, b)
  end

  def t([other_expr(e)], _v, c, _q, b) do
    c.(quote do unquote(e) ; unquote(b)._Zero() end)
  end
end
