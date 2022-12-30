procs = [:p1, :p2]
Enum.map(procs, fn p -> Paxos.start(p, procs) end)
result = Paxos.propose(:global.whereis_name(:p1), 1, {:hello, "world"}, 1000)
IO.inspect(result)
