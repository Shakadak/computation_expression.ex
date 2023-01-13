type TraceBuilder() =
    member this.Bind(m, f) =
        match m with
        | None ->
            printfn "Binding with None. Exiting."
        | Some a ->
            printfn "Binding with Some(%A). Continuing" a
        Option.bind f m

    member this.Return(x) =
        printfn "Returning a unwrapped %A as an option" x
        Some x

    member this.ReturnFrom(m) =
        printfn "Returning an option (%A) directly" m
        m

    member this.Zero() =
        printfn "Zero"
        None

    member this.Yield(x) =
        printfn "Yield an unwrapped %A as an option" x
        Some x

    member this.YieldFrom(m) =
        printfn "Yield an option (%A) directly" m
        m

    member this.Combine (a,b) =
        match a,b with
        | Some a', Some b' ->
            printfn "combining %A and %A" a' b'
            Some (a' + b')
        | Some a', None ->
            printfn "combining %A with None" a'
            Some a'
        | None, Some b' ->
            printfn "combining None with %A" b'
            Some b'
        | None, None ->
            printfn "combining None with None"
            None

    member this.Delay(f) =
        printfn "Delay"
        f()

// make an instance of the workflow
let trace = new TraceBuilder()

trace {
    yield 1
    return 2
    } |> printfn "Result for yield then return: %A"

trace {
    return 1
    return 2
    } |> printfn "Result for return then return: %A"
