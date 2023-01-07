#!/usr/bin/env bash

function clean_beam_files {
  if compgen -G "test/*.beam" > /dev/null; then
    rm test/*.beam || :
  fi
}

echo "Building paxos.ex..."
. build.sh
cp dist/paxos.ex test/paxos.ex

echo "Starting tests..."
clean_beam_files

#bash -c "cd test/; iex test_script.exs > /dev/null" || :
bash -c "cd test/; iex test_script.exs" || :

echo "Cleaning up..."
clean_beam_files
