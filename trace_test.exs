require Test.Trace
Test.Trace.compute do                       
  IO.puts("Part 1: About to return 1")        
  return 1                                    
  IO.puts("Part 2: after return has happened")
end
|> IO.inspect(label: "Result for Part 1 without Part 2")
