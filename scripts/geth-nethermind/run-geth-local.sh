#! /bin/sh
#
# Usage:
#
#  Setup Nethermind (see script "run-nethermind-any.sh"), wait for a while
#  and generate the "$enodes" file with "sh run-nethermind-any.sh enode"
#  by piping it into the "$enodes" file.
#
#  Then start this file as "sh run-geth-local.sh" in the go-ethereum
#  base folder.
#
#  Session logs are piped into "$datadir/local.log".

exe=./build/bin/geth
datadir=./datadir-kiln
enodes=../nethermind/nethermind-enode.txt

(
  set -x
  $exe \
    init ../merge-testnets/kiln/genesis.json geth \
    --datadir=$datadir
)

(
  {
    echo "["
    cat $enodes |
      awk '{print "  \"" $0 "\","}' |
      sed '${; s/,$//; }'
    echo "]"
  } > $datadir/geth/static-nodes.json 

  exec >&2
  echo

  mv $datadir/local.log $datadir/local.log~ 2>/dev/null || true
)

(
  set -x
  $exe \
    --datadir=$datadir \
    --networkid=1337802 \
    --netrestrict=127.0.0.0/8 \
    --nodiscover \
    --syncmode=full \
    --log.debug \
    --verbosity=5 \
    --nat=none \
    --port=30903 \
    --http.port=44441 \
    --ws.port=44442 \
    --authrpc.port=44443 \
    --ipcpath=./datadir-kiln/geth.ipc \
    2>&1
) | tee $datadir/local.log

# End
