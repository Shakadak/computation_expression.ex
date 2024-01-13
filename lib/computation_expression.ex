defmodule ComputationExpression do
  defmacro __using__(opts) do
    {debug?, []} = Keyword.pop(opts, :debug, false)
    #quote do
    #  defmacro compute(do: doo) do
    #    body = unquote(__MODULE__).normalize_body(doo)
    #    unquote(__MODULE__).root_build(__MODULE__, body, __CALLER__)
    #    |> case do x -> if unquote(debug?) do IO.puts(Macro.to_string(x)) end ; x end
    #  end
    #end

    quote do
      defmacro compute(do: doo) do
        body = unquote(__MODULE__).normalize_body(doo)
        unquote(__MODULE__).Translation.comp_expr(body, __MODULE__)
        |> case do x -> if unquote(debug?) do IO.puts(Macro.to_string(x)) end ; x end
      end
    end
  end

  defmacro compute(computation_builder, do: doo) do
    generate_ast(computation_builder, doo, [], __CALLER__)
  end
  defmacro compute(computation_builder, opts, do: doo) do
    generate_ast(computation_builder, doo, opts, __CALLER__)
  end

  @doc false
  def generate_ast(computation_builder, doo, opts, caller_env) do
    builder = normalize_computation_builder(computation_builder, caller_env)

    {debug?, []} = Keyword.pop(opts, :debug, false)

    body = __MODULE__.normalize_body(doo)
    __MODULE__.Translation.comp_expr(body, computation_builder, builder)
    |> case do x -> if debug? do IO.puts(Macro.to_string(x)) end ; x end
  end

  def normalize_computation_builder({:__aliases__, meta, aliases}, caller) do
    case Keyword.fetch(meta, :alias) do
      {:ok, false} -> Module.concat(aliases)
      {:ok, alias} -> alias
      :error ->
        case aliases do
          [x] -> case Macro.Env.fetch_alias(caller, x) do
            {:ok, module} -> module
            :error -> Module.concat(aliases)
          end
          xs -> Module.concat(xs)
        end
    end
  end

  defguard is_ce_form(x) when x in [
    :let!,
    :and!,
    :do,
    :yield,
    :yield!,
    :pure,
    :pure!,
    :match!,
    # Other
    :"\if",
  ]

  def normalize_body({:__block__, _context, body}) when is_list(body), do: body
  def normalize_body({_, _ctxt, _} = body), do: [body]

  def root_build(module, body, caller) do
    built = build(module, body, caller)
    case function_exported?(module, :delay, 1) do
      false -> built
      true ->
        quote do
          unquote(module).delay(fn -> unquote(built) end)
        end
    end
  end

  def build(_module, [], caller) do
    kind = CompileError
    opts = [
      file: caller.file,
      line: caller.line,
      description: "Computation expression cannot be empty.",
    ]
    raise kind, opts
  end

  def build(_module, [{:let!, context, _}], caller) do
    kind = CompileError
    opts = [
      file: caller.file,
      line: Keyword.get(context, :line, caller.line),
      description: "End of computation expression cannot be `let!`.",
    ]
    raise kind, opts
  end

  def build(module, [{:pure, _ctxt, args}], _caller) do
    quote do
      unquote(module).pure(unquote_splicing(args))
    end
  end

  def build(module, [{:pure!, _ctxt, args}], _caller) do
    quote do
      unquote(module).pure_from(unquote_splicing(args))
    end
  end

  def build(module, [{:yield, _ctxt, args}], _caller) do
    quote do
      unquote(module).yield(unquote_splicing(args))
    end
  end

  def build(module, [{:yield!, _ctxt, args}], _caller) do
    quote do
      unquote(module).yield_from(unquote_splicing(args))
    end
  end

  def build(module, [{:if, _ctxt, [cond, [{:do, cexpr}]]}], caller) do
    built1 = build(module, normalize_body(cexpr), caller)
    quote do
      if unquote(cond) do unquote(built1) else unquote(module).zero() end
    end
  end

  def build(module, [{:if, _ctxt, [cond, [{:do, cexpr}, {:else, cexpr2}]]}], caller) do
    built1 = build(module, normalize_body(cexpr), caller)
    built2 = build(module, normalize_body(cexpr2), caller)
    quote do
      if unquote(cond) do unquote(built1) else unquote(built2) end
    end
  end

  def build(module, [line], _caller) do
    quote do
      unquote(line)
      unquote(module).zero()
    end
  end

  def build(module, [{:let!, _ctxt, [{:=, _ctxt2, [binding, expression]}]} | tail], caller) do
    quote location: :keep do
      unquote(expression)
      |> unquote(module).bind(fn unquote(binding) ->
        unquote(build(module, tail, caller))
      end)
    end
  end

  def build(module, [{:do!, _ctxt, [expression]} | tail], caller) do
    quote location: :keep do
      unquote(expression)
      |> unquote(module).bind(fn _ -> # Should be unit: {}
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

  def build(module, [{ce_form1, _ctxt, _} = head | [{ce_form2, _ctxt2, _} | _] = tail], caller) when is_ce_form(ce_form1) and is_ce_form(ce_form2) do
    built1 = build(module, [head], caller)
    built2 = build(module, tail, caller)
    quote location: :keep do
      unquote(module).combine(unquote(built1), unquote(module).delay(fn -> unquote(built2) end))
    end
  end

  # T([ce1| ce2, V, C, q) = C(b.Combine({| ce1 |}0, b.Delay(fun () -> {| ce2 |}0)))

  # def build(module, [line | tail], caller) do
  #   built = build(module, tail, caller)
  #   quote location: :keep do
  #     unquote(line)
  #     unquote(built)
  #   end
  # end
end
