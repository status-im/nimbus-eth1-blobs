#! /bin/sh
#
# Start/manage multiple Nethermind instances for "kiln" network
#
# Preparation:
#
#     git clone \
#       --recursive -b kiln --depth 1 \
#       https://github.com/NethermindEth/nethermind.git \
#       n0
#
#     cd n0/src/Nethermind
#     dotnet build Nethermind.sln -c Release
#
# Note that "n0" is the first clone directory.

self=`basename $0`

# Cloned Nethermind directories: ${prefix}0, ${prefix}1, etc.
prefix=n

# Clone instances for "clone" option
clone_instances="0 1 2 3"

# The network to use
name=kiln

# ------------------------------------------------------------------------------
# No need to change, below
# ------------------------------------------------------------------------------

logfile_max=80000000
num_backlogs=40

# List of available clones
dir_list=`ls -d ${prefix}[0-9] 2>/dev/null`

# First and second clone (for generator)
clone0=`echo $clone_instances | awk '{print "'"$prefix"'" $1}'`
clone1=`echo $clone_instances | awk '{print "'"$prefix"'" $2}'`
clone_list=`echo $clone_instances | awk '
                BEGIN {RS = " "}
                $1 ~ /[0-9]/ {if(a) {print "'"$prefix"'" $1} else {a=1}}'`

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

get_pid_svlogd() { # Syntax: <datadir>
    ps x|
	grep \
	    -e "svlogd $1/log" \
        |
	grep -v \
	     -e vim \
	     -e grep \
        |
	awk '$1 != '"$$"'{print $1}'
}

get_pids() {
    for dir in $dir_list
    do
        instance=`expr "$dir" : '.*[^0-9]\([0-9]\)$'`
        datadir=datadir-$name$instance
        secret=$PWD/$datadir/jwtsecret

        # Set ports dependent on instance
        htport=`expr 8545 + $instance \* 10`
        wsport=`expr 8546 + $instance \* 10`

        ps x |
          grep -e 'dotnet run' |
          grep -e JsonRpc.JwtSecretFile=$secret

	ps x |
          grep -e net6.0/Nethermind.Runner |
	  grep -e "JsonRpc.Port=$htport --JsonRpc.WebSocketsPort=$wsport"

        ps x |
          grep -e "svlogd $datadir/log"
    done |
      grep -v \
        -e vim \
	-e grep |
      awk '$1 != '"$$"' {print $1}'
}

# ------------------------------------------------------------------------------
# Command line parsing and man page
# ------------------------------------------------------------------------------

stop=no
start=no
flush=no
enode=no
clone=no
help=no

test $# -ne 0 ||
    help=yes

for arg
do
    case "$arg" in
    enode)
	enode=yes
	;;
    clone)
	clone=yes
	;;
    stop)
	stop=yes
	;;
    flush)
	flush=yes
	stop=yes
	;;
    start)
	start=yes
	;;
    help|'')
	help=yes
	;;
  *)
      exec >&2
      echo "Usage: $self [help] [clone] [stop] [flush] [start] [enode]"
      exit 2
  esac
done

test yes != "$help" || {
    cat <<EOF
$self:
   Available commands (can be combined irrespective of order):
      clone   duplicate/copy directory $clone0 to $clone1, ...
      stop    stop the Nethemind sessions
      flush   delete all log and blockchain data (implies stop)
      start   start the Nethermind sessions
      enode   grep self-node addresses from log files
EOF
    exit
}

# ------------------------------------------------------------------------------
# MAIN
# ------------------------------------------------------------------------------

test yes != "$stop" || {
    pids=`get_pids`
    test -z "$pids" || {
       (set -x; kill -TERM $pids)
       (set -x; killall /usr/share/dotnet/dotnet)
       sleep 1
       pids=`get_pids`
       test -z "$pids" || {
          (set -x; kill -KILL $pids)
          sleep 1
       }
       echo
    }
}

test yes != "$flush" || {
    for dir in $dir_list
    do
        instance=`expr "$dir" : '.*[^0-9]\([0-9]\)$'`

        datadir=datadir-$name$instance
        rundir=$dir/src/Nethermind/Nethermind.Runner

	for subdir in \
	  "$rundir/bin/Release/net6.0/logs" \
          "$rundir/bin/Release/net6.0/nethermind_db" \
	  "$datadir" \
	; do

	    test -d "$subdir" || continue
	    (set -x; rm -rf "$subdir")
        done
    done
}

test yes != "$clone" || {
    for dir in $clone_list
    do
	test \! -d "$dir" || (
	    rm -rf "$dir~"
	    set -x
	    mv "$dir" "$dir~" 2>/dev/null
	)
	(set -x; cp -r "$clone0" "$dir")
    done
}
    
test yes != "$start" || {
    for dir in $dir_list
    do
        instance=`expr "$dir" : '.*[^0-9]\([0-9]\)$'`

        datadir=datadir-$name$instance
        rundir=$dir/src/Nethermind/Nethermind.Runner
        config=$rundir/configs/$name.cfg

        # Set ports dependent on instance
        port=`expr 30403 + $instance`
        htport=`expr   8545 + $instance \* 10`
        wsport=`expr   8546 + $instance \* 10`
        authport=`expr 8551 + $instance \* 10`

        rpcurls=
        # rpcurls="$rpcurls${rpcurls:+,}http://localhost:$wsport|http;ws|net;eth;subscribe;engine;web3;client|no-auth"
        rpcurls="$rpcurls${rpcurls:+,}http://localhost:$authport|http;ws|net;eth;subscribe;engine;web3;client"

        mkdir -p $datadir/log $datadir/data
	
        # Fixed session secret depending on instance
        secret=$PWD/$datadir/jwtsecret
        echo $instance |
          awk '{for(n=0;n<32;n++){a=a"ab"}print substr(a$1,1+length($1))}' |
          tee "$secret" > /dev/null
	
	# Fixed node key depending on instance
	node_key=`echo $instance |
          awk '{for(n=0;n<32;n++){a=a"cd"}print substr(a$1,1+length($1))}'`

        (
	    (
                cd $datadir

                mv ./log/config ./log/config~ 2>/dev/null || true
                {
                   echo s$logfile_max
                   echo n$num_backlogs
                } >./log/config
            )

	    (
                cd "$rundir"

	        set -x
                dotnet \
	          run -c Release -- \
	          --config=$name \
	          --JsonRpc.Host=127.0.0.1 \
	          --JsonRpc.Port=$htport \
	          --JsonRpc.WebSocketsPort=$wsport \
	          --JsonRpc.JwtSecretFile=$secret \
	          --JsonRpc.AdditionalRpcUrls=$rpcurls \
	          --Network.P2PPort=$port \
	          --Network.DiscoveryPort=$port \
		  --KeyStore.TestNodeKey=$node_key \
	          2>&1
	    ) | ansi2txt | svlogd $datadir/log
        ) &

	sleep 1
        pid=`get_pid_svlogd $datadir`
        test -z "$pid" || kill -HUP $pid
        echo >&2
    done
}


test yes != "$enode" || {
    for dir in $dir_list
    do
	grep -R enode datadir-$name[0-9] | grep 'This node'
    done |
	awk '{print $NF}' |
	sort -u
}

# ------------------------------------------------------------------------------
# End
# ------------------------------------------------------------------------------
