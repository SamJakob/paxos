procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
Paxos.propose(:global.whereis_name(:p1), 1, {:hello, "world"}, 1000)
decision = Paxos.get_decision(Enum.at(pids, 2), 1, 500)
IO.puts("decision = " <> inspect(decision))
