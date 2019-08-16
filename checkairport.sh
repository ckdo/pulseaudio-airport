#!/bin/bash

AIRPORT_IP="192.168.128.40"
PULSE_RUNTIME_PATH=/var/lib/pulse
[ -n "$1" ] && AIRPORT_IP="$1"
STATE="inactive"
CURRENT_DIR=$(cd $( dirname ${BASH_SOURCE[0]}) && pwd )

# GLOBAL SCOPE VARIABLES
global_sink_inputs="" 
global_sink_inputs_short="" 
global_sinks="" 
global_sinks_short="" 

function checkairport(){
  socat -d - TCP:$AIRPORT_IP:5000,crlf <<EOF
ANNOUNCE rtsp://192.168.128.112/3640071595 RTSP/1.0
Client-computer-name: LAPTOP-IL5DHO2A
Content-Type: application/sdp
Content-Length: 577
CSeq: 2
User-Agent: iTunes/7.6.2 (Windows; N;)
Client-Instance: 1FFAF0B272F015D0
DACP-ID: 5BCBE4FF64A5B675
Client-instance-identifier: f82625af-7038-42ca-9208-38edecaccaf0

v=0
o=iTunes 3640071595 O IN IP4 192.168.128.112
s=iTunes
c=IN IP4 192.168.128.23
t=0 0
m=audio 0 RTP/AVP 96
a=rtpmap:96 AppleLossless
a=fmtp:96 352 0 16 40 10 14 2 255 0 0 44100
a=rsaaeskey:Gr8qH5+zsUtaMxUYMMgoZQbqt06ALtW7FD916WSnEBW8mRNypyRO13a4D5bUaVH2HOcYHYNO49jAn6zmIJo4IpdqBAkVXqLfSQAU3WlPJxleLJhNtMJv/yn0v8gD6lFBZhhDhxgHyUCrYbI63SZhSoZv8aiFyh/RE1XQFmDsbt/QzkjIWy5zXbkPNX227UP7/b1s9gwRbPYVmD29fyt3cjhJageU64hTDAOYgECQ6TCo9zQMoRTNQzdQLpcxfoDLctGuBZExByyoBEkroh0cD+JQFKrO1aPf5g9HWF9Gqo0cGrrb9JknPjYPoI0Rr3uegjU717+R1WippeQJiIporw
a=aesiv:AAECAwQFBgcICQoLDA0ODw

EOF

  socat -d - TCP:$AIRPORT_IP:5000,crlf <<EOF > /dev/null
TEARDOWN rtsp://192.168.128.112/3640071595 RTSP/1.0
CSeq: 3
User-Agent: iTunes/10.6 (Macintosh; Intel Mac OS X 10.7.3) AppleWebKit/535.18.5
Client-Instance: 1FFAF0B272F015D0
DACP-ID: 5BCBE4FF64A5B675

EOF
}

# get the volume of a sink name in arg
function getVolume(){
  fromsink=$(echo "$global_sinks_short" | grep $1 | cut -d$'\t' -f1)
  goodsink=0
  
  echo "$global_sink_inputs"  | while read line
  do
    sinkline=`echo $line | grep -i "^Sink:"`
    if [ $? -eq 0 ]
    then
      if [ "$line"  = "Sink: $fromsink" ]
      then
        goodsink=1
      else
        goodsink=0
      fi
    fi
    if [ $goodsink -eq 1 ]
    then
      if [ $? -eq 0 ]
      then
        volume=$(echo $line | grep Volume | cut -d'/' -f1 | cut -d':' -f3 | sed -e s/[[:blank:]]//g)
        [ -n "$volume" ] && echo $volume && return
      fi
    fi
  done
}

function getstreams(){
  # Get sinkinput, sink, volume, corked in the following format
  # SinkInput#4;Sink:3;Corked:yes;75%
  echo "$global_sink_inputs" | grep -o "Sink: [0-9]*\|Corked: .*\|Sink Input #[0-9]*\|Volume: .*" | tr -d ' ' | sed 's/.*\/\([0-9]*%\).*/\1*/'  | tr '\n' ';' | sed s/*\;/\\n/g
}

# echo 1 if at least one stream is found on arg1
function checkstreams(){
  streamfound=0
  fromsink=$(echo "$global_sinks_short" | grep $1 | cut -d$'\t' -f1)
  getstreams | grep "Sink:$fromsink;" | grep -c "Corked:no" 
}

function restoreFakePulseDb(){
  echo "Reset stream-restore module DB"
  $CURRENT_DIR/reset_pulseaudio_restore.py 
}

# move sink inputs from sink $1 to sink $2
# if $3 is true, then filter corked streams 
# $4(optional) : Volume to be set 

function movestreams() {
  fromsink=$(echo "$global_sinks_short" | grep $1 | cut -d$'\t' -f1)
  streams=$(getstreams | grep "Sink:$fromsink;")
  if [ "$3" == "true" ]
  then
    streams=$(echo "$streams" | grep "Corked:no") 
  fi  

  while read -r line
  do
    if [ -n "$line" ]
    then
    sinkinput=$(echo $streams | cut -d';' -f1 | cut -d'#' -f2)
    echo "Found stream to switch to $2 : $sinkinput"
    [ -n "$4" ] && echo "Setting volume of sinkinput $sinkinput to $4" && pactl set-sink-input-volume $sinkinput $4
    pactl move-sink-input $sinkinput $2 
    fi
  done< <(echo "$streams")
}

restoreflag="true"
echo "Starting..."
while [ 1 -eq 1 ]
do 
  global_sink_inputs=$(pactl list sink-inputs)
  global_sink_inputs_short=$(pactl list short sink-inputs)
  global_sinks=$(pactl list sinks)
  global_sinks_short=$(pactl list short sinks)

  airportThere=`ping -c 3 $AIRPORT_IP`

#if [ 1 -eq 1 ]
if [ "$?" -ne "0" ]
then
  # AirPort Down
  movestreams AirPort-Express-de-Christophe fakeairport false
  loadedModuleCounts=$(pactl list modules | grep -c -i module-raop-sink)
  if [ "$loadedModuleCounts" -gt 0 ]
  then
    echo "Unload module Raop"
    pactl unload-module module-raop-sink
    # Reset fakeairport by default
    restoreFakePulseDb
  fi
else
  # AirPort Up
  loadedModuleList=$(pactl list modules)
  # If any trouble to connect, do not load module
  if [ $? -eq 0 ]
  then
    loadedModuleCounts=$(echo "$loadedModuleList" | grep -c -i module-raop-sink)
    if [ "$loadedModuleCounts" -eq "0" ]
    then
      echo "Load module Raop"
      pactl load-module module-raop-sink server=$AIRPORT_IP:5000 sink_name=AirPort-Express-de-Christophe protocol=UDP encryption=RSA codec=ALAC channels=2 format=16 rate=44100 latency_msec=2000
      echo "Waiting AirPort to be ready..."
      sleep 15
    fi
  fi
 
  currentAirportStreamCount=`checkstreams AirPort-Express-de-Christophe` 
  
  if [ "$previousAirportStreamCount" == "0" -a "$currentAirportStreamCount" == "0" ]
  then
    if [ "$restoreflag" == "true" ]
    then
      # If up but no stream since a while 
      echo "No stream on Airport since last cycle, restoring fake as default"
      # if now stream since last time, switch to fake by default 
      restoreFakePulseDb 
      restoreflag="false"
      # checkstreams returns no active stream but we may have corked stream
      movestreams AirPort-Express-de-Christophe fakeairport false 
    fi
  else
    restoreflag="true"
  fi 
  if [ "$currentAirportStreamCount" == "0" ]
  then
    # If not busy by other AirPlay Client, return 200 OK
    echo "Checking if airport is busy"
    checkairport | grep -q 200
    if [ $? -eq 0 ]
    then
      currentVolume=`getVolume alsa_output.usb-Burr-Brown_from_TI_USB_Audio_DAC-00.analog-stereo`
      movestreams fakeairport AirPort-Express-de-Christophe true $currentVolume
    fi
  fi
  previousAirportStreamCount=$currentAirportStreamCount
fi
  #echo "Waiting for next cycle..."
  sleep 5 
done
