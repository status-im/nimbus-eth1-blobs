#! /bin/sh

self=${NIMBUS_SESSION_SELF:-`basename "$0"`}

# Prefix nimbus command, e.g. gdbserver
exepfx=${NIMBUS_EXEPFX}

# Network name (used below for easy setup)
name=${NIMBUS_SESSION_NAME:-mainnet}

# Unique Nimbus TCP/UDP communication port
port=${NIMBUS_SESSION_PORT:-30308}

# Unique Nimbus websocket ports base
aws_port=${NIMBUS_SESSION_AWSPORT:-8551}

# Unique log data and database folder (relative to current directory)
datadir=${NIMBUS_SESSION_DATADIR:-./datadir-nimbus-$name}

# # Enable websockets, rpc, etc,
exelayer=${NIMBUS_SESSION_EXELAYER:-no}

# Connect locally without discovery, static peer file as argument
localpeer=${NIMBUS_SESSION_LOCALPEER}

# Override nimbus-eth1 dir
nimbus_eth1=${NIMBUS_SESSION_ETH1DIR:-nimbus-eth1}

# Override shared RPC secret
jwtsecret=${NIMBUS_SESSION_JWTSECRET:-./jwtsecret}

# Generic options
optargs=${NIMBUS_SESSION_OPTARGS:-'--nat=None'}

# ------------------------------------------------------------------------------
# No need to change, below
# ------------------------------------------------------------------------------

# Name of custom genesis and bootstrap files
genesis_json=$name.json
bootstrap_txt=$name-enode.txt

# Log spooler capacity settings
logfile_max=80000000
num_backlogs=40

# Base directory for finding objects in the Nimbus file system
find_prefix="`dirname $0` . .. ../.."
find_prefix="$find_prefix    $nimbus_eth1    nimbus-eth1-blobs"
find_prefix="$find_prefix ../$nimbus_eth1 ../nimbus-eth1-blobs"

# Sub-find directory for various items
find_nimbus=". .. build"
find_genesis=". .. customgenesis"
find_bootstrap=". .. custom-network"

# Local peer file, connect locally without discovery
test -z "$localpeer" || {
  optargs="$optargs --static-peers-file=$localpeer"
  optargs="$optargs --discovery=None"
  optargs="$optargs --listen-address=127.0.0.1"
  optargs="$optargs --min-sync-peers=1"
  optargs="$optargs --nat=None"
}

# Sanitise shared secret file name
case $jwtsecret in
/tmp/*|/home/*|/*/nimbus-eth1/*|./jwtsecret)
    ;;
./log/*|log/*)
    jwtsecret="./log/`basename $jwtsecret`"
    ;;
./data/*|data/*)
    jwtsecret="./data/`basename $jwtsecret`"
    ;;
*)  jwtsecret="./`baseame $jwtsecret`"
esac

# Run an Execution Layer Client (using the same ports as geth)
test yes != "$exelayer" || {
    rpc_port=`expr $aws_port - 6`  # 8545
    ws_port=` expr $aws_port - 5`  # 8546
    api_port=`expr $aws_port - 1`  # 8550

    #optargs="$optargs --ws=true"
    #optargs="$optargs --ws-port=$ws_port"

    #optargs="$optargs --rpc=true"
    #optargs="$optargs --rpc-port=$rpc_port"

    optargs="$optargs --engine-api=true"
    optargs="$optargs --engine-api-port=$api_port"

    optargs="$optargs --engine-api-ws=true"
    optargs="$optargs --engine-api-ws-port=$aws_port"

    optargs="$optargs --jwt-secret=$jwtsecret"
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# Find executable file
find_exe() { # Syntax: <exe-name> <subdir> ...
    exe="$1"
    shift
    {
	for pfx in $find_prefix; do
	    for sub; do
		find -L \
		     "$pfx/$sub" \
		     -maxdepth 3 -type f -name "$exe" -perm /111 -print \
		     2>/dev/null
	    done
	done |
	    # Beware, this is slow. On the other hand, uncommenting the
	    # next line dumps all possible matches to the console.
	    #tee /dev/tty |
	    xargs -n1 realpath 2>/dev/null
	# provide argument file name as default
	echo "$exe" 2>/dev/null
    } |	sed -eq
}

# Find non-executable file
find_file() { # Syntax: <file-name> <subdir> ...
    file="$1"
    shift
    {
	for pfx in $find_prefix; do
	    for sub; do
		find -L \
		     "$pfx/$sub" \
		     -maxdepth 3 -type f -name "$file" -print \
		     2>/dev/null
	    done |
		# Beware, this is slow. On the other hand, uncommenting the
		# next line dumps all possible matches to the console.
		#tee /dev/tty |
		xargs -n1 realpath 2>/dev/null
	done
	# provide argument file name as default
	echo "$file"
    } | sed -eq
}

stripColors() {
  if ansi2txt </dev/null 2>/dev/null
  then
      ansi2txt
  else
      cat
  fi
}

# Find pid of running svlogd command
get_pid_svlogd() {
    ps x|
	grep \
	    -e "svlogd $datadir/log" \
        |
	grep -v \
	     -e vim \
	     -e grep \
        |
	awk '$1 != '"$$"'{print $1}'
}

# Find pid of running svlogd and nimbus command
get_pids() {
    ps x|
	grep \
	    -e "nimbus .* --tcp-port:$port" \
	    -e "svlogd $datadir/log" \
        |
	grep -v \
	     -e vim \
	     -e grep \
        |
	awk '$1 != '"$$"'{print $1}'
}

# ------------------------------------------------------------------------------
# Command line parsing and man page
# ------------------------------------------------------------------------------

nohup=no
start=no
stop=no
flush=no
logs=no
help=no

test $# -ne 0 ||
    help=yes

for arg
do
    case "$arg" in
    stop)
	stop=yes
	;;
    flush)
	flush=yes
	;;
    start)
	start=yes
	;;
    daemon)
	nohup=yes
	start=yes
	;;
    logs)
	logs=yes
	;;
    help|'')
	help=yes
	;;
  *)
      exec >&2
      echo "Usage: $self [help] [stop] [flush] [daemon|start] [logs]"
      exit 2
  esac
done


test yes != "$help" || {
    cat <<EOF
$self:
   The script manages a Nimbus session for Mainnet. It was inspired by running
   a test node remotely on a cloud exposed server for syncing. The script will
   start the "nimbus" program and maintain database and log files in the folder
   $datadir.

   The script must be run from the "nimbus-eth1" base directory or from one of
   its sub-directories. In the simple case, the script is run as

     sh $self start

   which will run Nimbus in the background and print the logs on the console.
   With ctrl-C, the program is stopped. In order to run in the background, the
   the "nimbus" program is started with

     sh $self daemon

   Continuous logging can then be displayed on the console (hit ctrl-C to stop)
   with

      sh $self logs

   A running background session is stopped with

      sh $self stop

   Log data are held in sort of a fifo and can be inspected with

      cat $datadir/log/* | less

   Available commands (can be combined irrespective of order):
      logs    resume console logging (as descibed above)
      flush   delete all log and blockchain data

   Mutually exclusive commands:
      stop    stop the Nimbus session (as descibed above)
      start   start the Nimbus session in the foreground
      daemon  background session (without termninating on logout, e.g. from ssh)
EOF
    exit
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

# Check for logger program availability
(svlogd 2>&1|grep -i 'usage: svlogd' >/dev/null) || {
  exec >&2
  echo "*** $self: This script needs a working \"svlogd\" program. On Debian,"
  echo "                    this is provided by the \"runit\" package."
  exit 2
}

# Stop running sessions by sending termination signal
test yes != "$stop" || {
  # set -x
  pids=`get_pids`
  test -z "$pids" || {
      (set -x; kill -TERM $pids)
      sleep 1
      pids=`get_pids`
      test -z "$pids" || {
	  (set -x; kill -KILL $pids)
	  sleep 1
      }
      echo
  }
}

# Clean up
test yes != "$flush" || {
  d=`basename $datadir`
  test \! -d $datadir || (set -x; rm -rf $datadir)
}

# Stop here after clean up when terminating a session
test yes != "$stop" || {
  exit
}

if [ yes = "$nohup" ]
then
  # Restore console after disabling ctrl-C for nimbus
  stty_save=`stty --save </dev/tty`
elif [ yes != "$flush" ]
then
  # Set logging unless deamon enabled
  logs=yes
fi

# Start a new nimbus session in the background
test yes != "$start" || (
  mkdir -p $datadir/log $datadir/data

  nimbus=`find_exe nimbus $find_nimbus`
  bootstrap=`find_file $bootstrap_txt $find_bootstrap`

  case "$name" in
  mainnet|ropsten|rinkeby|goerli|kovan|sepolia)
      optargs="$optargs --network=$name"
      ;;
  *) genesis=`find_file $genesis_json $find_genesis`
     optargs="$optargs --custom-network=$genesis"
     optargs="$optargs --bootstrap-file=$bootstrap"
  esac

  # RPC authorisation seed, might not be needed though
  case $jwtsecret in
  /tmp/*|/home/*|/*/nimbus-eth1/*)
     dirpfx= ;;
  *) dirpfx="$datadir/"
  esac
  test yes != "$exelayer" -o -s "$dirpfx$jwtsecret" || (
      umask 377
      rm -f "$dirpfx$jwtsecret"
      {
	  echo 0x
	  openssl rand -hex 32
	  # echo $session_key
      } | tr -d '\n' > "$dirpfx$jwtsecret"
  )

  test yes != "$nohup" || {
     trap "echo '*** $self: NOHUP ignored'" HUP
     trap "echo '*** $self: terminating ..';exit"  INT TERM QUIT
     stty intr "" </dev/tty
  }
  (
    cd $datadir

    mv ./log/config ./log/config~ 2>/dev/null || true
    {
       echo s$logfile_max
       echo n$num_backlogs
    } >./log/config

    set -x
    ${exepfx} ${nimbus:-nimbus} \
      --data-dir:./data \
      --tcp-port:$port \
      $optargs \
      --log-level:TRACE \
      2>&1

  ) | stripColors | svlogd $datadir/log
) &

# After starting a session, make sure that svlogd is re-loaded in order
# to read the config file (woul not tdo it right on the start)
test yes != "$start" || {
    sleep 1
    pid=`get_pid_svlogd`
    test -z "$pid" || kill -HUP $pid
    echo
}

# Restore console after disabling ctrl-C for nimbus
test yes != "$nohup" || {
    stty $stty_save </dev/tty
}

# Logging ...
test yes != "$logs" || {
  mkdir -p $datadir/log/
  touch $datadir/log/current |
  tail -F $datadir/log/current |

    # Filter out chaff on console data
    grep -v \
      -e 'auth: ECIES encryption/decryption error' \
      -e 'Bonding to peer' \
      -e 'Connecting to node' \
      -e 'file=discovery.nim:' \
      -e 'file=kademlia.nim:' \
      -e 'Waiting for more peers' \
      -e 'dropped in rlpxAccept.*remote=Node\[local\]' \
      -e 'Discarding New' \
      -e 'Discarding Trans' \
      -e '>>> [pf][io]' \
      -e '<<< [pf][io]'
}

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
