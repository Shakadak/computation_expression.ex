type ListBuilder() =
    member this.Bind(m, f) =
        m |> List.collect f

    member this.Zero() =
        printfn "Zero"
        []

    member this.Yield(x) =
        printfn "Yield an unwrapped %A as a list" x
        [x]

    member this.YieldFrom(m) =
        printfn "Yield a list (%A) directly" m
        m

    member this.For(m,f) =
        printfn "For %A" m
        this.Bind(m,f)

    member this.Combine (a,b) =
        printfn "combining %A and %A" a b
        List.concat [a;b]

    member this.Delay(f) =
        printfn "Delay"
        f()

// make an instance of the workflow
let listbuilder = new ListBuilder()