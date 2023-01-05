require Logger

procs = [:p1, :p2, :p3]
pids = Enum.map(procs, fn p -> Paxos.start(p, procs) end)
Paxos.propose(:global.whereis_name(:p1), 1, {:hello, "world"}, 1000)

decision = Paxos.get_decision(Enum.at(pids, 2), 1, 500)
Logger.flush()
Process.sleep(100)
IO.puts("decision (instance 1) = #{inspect(decision)}")

Process.sleep(1000)

p_fun = fn n, i, v, t -> (
  fn -> Paxos.propose(:global.whereis_name(n), i, v, t) end
) end

Process.sleep(600)

spawn(p_fun.(:p1, 2, :hola, 500)); spawn(p_fun.(:p2, 2, :hi, 500))

# Wait for Paxos to finish. (Ordinarily this test would be entered into iex
# manually, so we must do this to ensure enough time has passed.)
Process.sleep(600)

decision = Paxos.get_decision(Enum.at(pids, 2), 2, 1000)
Logger.flush()
Process.sleep(100)
IO.puts("decision (instance 2) = #{inspect(decision)}")

Process.sleep(100)

Enum.each(pids, fn p -> Process.exit(p, :kill) end)
