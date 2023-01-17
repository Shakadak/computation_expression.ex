defmodule ComputationExpressions.Translation do
  alias ComputationExpressions.Translation.Auxiliary

  import Auxiliary, only: [
    var: 1,
    src: 2,
    assert: 1,
  ]

  def comp_expr(ast, b) do
    new_ast = translate_with_custom(ast, b)
    if Module.open?(b) do
      new_ast = case Module.defines?(b, {:delay, 1}, :def) do
        true -> quote do unquote(b).delay(fn -> unquote(new_ast) end) end
        false -> new_ast
      end
      new_ast = case Module.defines?(b, {:quote_, 1}, :def) do
        true -> b.quote(new_ast)
        false -> new_ast
      end
      new_ast = case Module.defines?(b, {:run, 1}, :def) do
        true -> quote do unquote(b).run(unquote(new_ast)) end
        false -> new_ast
      end
      new_ast
    else
      new_ast = case function_exported?(b, :delay, 1) do
        true -> quote do unquote(b).delay(fn -> unquote(new_ast) end) end
        false -> new_ast
      end
      new_ast = case function_exported?(b, :quote_, 1) do
        true -> b.quote(new_ast)
        false -> new_ast
      end
      new_ast = case function_exported?(b, :run, 1) do
        true -> quote do unquote(b).run(unquote(new_ast)) end
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

  def t([{:let, _ctxt, [{:=, _ctxt2, [p, e]}]} | [_|_] = ce], v, c, q, b) do
    t(ce, MapSet.union(v, var(p)), fn expr -> c.(quote do unquote(p) = unquote(e) ; unquote(expr) end) end, q, b)
  end

  def t([{:let!, _ctxt, [{:=, _ctxt2, [p, e]}]} | [_|_] = ce], v, c, q, b) do
    t(ce, MapSet.union(v, var(p)), fn expr -> c.(quote do unquote(b).bind(unquote(src(e, b)), fn unquote(p) -> unquote(expr) end) end) end, q, b)
  end

  def t([{:yield, _ctxt, [e]}], _v, c, _q, b) do
    c.(quote do unquote(b).yield(unquote(e)) end)
  end

  def t([{:yield!, _ctxt, [e]}], _v, c, _q, b) do
    c.(quote do unquote(b).yield_from(unquote(e)) end)
  end

  def t([{:return, _ctxt, [e]}], _v, c, _q, b) do
    c.(quote do unquote(b).return(unquote(e)) end)
  end

  def t([{:return!, _ctxt, [e]}], _v, c, _q, b) do
    c.(quote do unquote(b).return_from(unquote(e)) end)
  end

  def t([{:use, _ctxt, [{:=, _ctxt2, [p, e]}]} | [_|_] = ce], _v, c, _q, b) do
    c.(quote do unquote(b).using(unquote(e), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end)
  end

  def t([{:use!, _ctxt, [{:=, _ctxt2, [p, e]}]} | [_|_] = ce], _v, c, _q, b) do
    c.(quote do unquote(b).bind(unquote(src(e, b)), fn unquote(p) -> unquote(b).using(unquote(p), fn unquote(p) -> unquote(translate_basic(ce, b)) end) end) end)
  end

  def t([{:match, _ctxt, [e, do: cls]}], _v, c, _q, b) do
    clauses = Enum.flat_map(cls, fn {:->, _, [[pi], cei]} ->
      ncei = ComputationExpressions.normalize_body(cei)
      quote do unquote(pi) -> unquote(translate_basic(ncei, b)) end
    end)
    c.(quote do case unquote(e) do unquote_splicing(clauses) end end)
  end

  def t([{:match!, _ctxt, [e, do: cls]}], v, c, q, b) do
    t(quote do
      let! x = unquote(e)
      match x do unquote_splicing(cls) end
    end, v, c, q, b)
  end

  def t([{:while, _ctxt, [e, do: ce]}], v, c, q, b) do
    nce = ComputationExpressions.normalize_body(ce)
    t(nce, v, fn expr -> c.(quote do unquote(b).while(fn -> unquote(e) end, unquote(b).delay(fn -> unquote(expr) end)) end) end, q, b)
  end

  # try with

  # try finally

  def t([{:if, _ctxt, [e, do: ce]}], v, c, q, b) do
    nce = ComputationExpressions.normalize_body(ce)
    t(nce, v, fn expr -> c.(quote do if unquote(e) do unquote(expr) else unquote(b).zero() end end) end, q, b)
  end

  def t([{:if, _ctxt, [e, do: ce1, else: ce2]}], _v, c, q, b) do
    assert(not q)
    nce1 = ComputationExpressions.normalize_body(ce1)
    nce2 = ComputationExpressions.normalize_body(ce2)
    c.(quote do if unquote(e) do unquote(translate_basic(nce1, b)) else unquote(translate_basic(nce2, b)) end end)
  end

  # for to
  # for joinOp
  # for groupJoinOp
  # for

  def t([{:do_, _ctx, [e]} | [_|_] = ce], v, c, q, b) do
    t(ce, v, fn expr -> c.(quote do unquote(e) ; unquote(expr) end) end, q, b)
  end

  def t([{:do!, _ctx, [e]} | [_|_] = ce], v, c, q, b) do
    t(quote do let! {} = unquote(e) ; unquote(ce) end, v, c, q, b)
  end

  # joinOp
  # groupJoinOp
  # customOperator
  # customOperator(maintainsVarSpaceUsingBind) ; e
  # customOperator ; e

  def t([ce1 | [_|_] = ce2], _v, c, _q, b) do
    c.(quote do unquote(b).combine(unquote(translate_basic([ce1], b)), unquote(b).delay(fn -> unquote(translate_basic(ce2, b)) end)) end)
  end

  def t([{:do!, _ctx, [e]}], v, c, q, b) do
    t(quote do let! {} = unquote(src(e, b)) ; unquote(b).return({}) end, v, c, q, b)
  end

  def t([e], _v, c, _q, b) do
    c.(quote do unquote(e) ; unquote(b).zero() end)
  end
end
