#! /bin/sh
#
# Parse raw nimbus-eth1 logs and extract client IDs from connection information.
# List all clients that delivered some sync data. Also, find out whether data
# provided were sent as chunked messages.
#
# Non-efficient programming -- but it does the job

datadir=datadir-nimbus-${1:-kiln}

# --------------------

blanks="                                               "

case `echo -e ''` in
-e*) say=echo ;;
*)   say='echo -e'
esac

stripColors() {
  if ansi2txt </dev/null 2>/dev/null
  then
      ansi2txt
  else
      cat
  fi
}

dump_data() {
  cat $datadir/log/* | stripColors
}

filter_nodes() {
  sed \
    -e '/ Requesting block headers /!d' \
    -e '/ peer=enode:/!d' \
    -e 's/.*@//'
}

filter_client_id() { # Syntax: <node>
  sed \
    -e '/ peer=Node\['"$1"'\] /!d' \
    -e '/ clientId=/!d' \
    -e 's/.* clientId=\([^ ]*\).*/\1/' \
    -eq
}

filter_chunked() { # Syntax: <node>
  sed \
    -e '/ peer=Node\['"$1"'\] /!d' \
    -e '/ chunked /!d' \
    -e 's/.*/chunked/' \
    -eq
}

# --------------------

dump_data |
  filter_nodes |
  sort -u |
  (
    while
      read node
    do
      cid=`dump_data | filter_client_id $node` 
      chk=`dump_data | filter_chunked $node`
      $say "\r*** $node $cid $chk $blanks\r\c" >&2
      echo $cid $chk
    done
    $say "\r$blanks$blanks$blanks\r\c" >&2
  ) |
  sort |
  uniq -c

# End
