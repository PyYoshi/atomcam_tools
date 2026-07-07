#!/bin/sh

# Upload a snapshot to Prusa Connect Camera API periodically.
# https://connect.prusa3d.com/docs/cameras/camera_communication/

HACK_INI=/tmp/hack.ini
PRUSA_ENABLE=$(awk -F "=" '/^PRUSA_ENABLE *=/ {print $2}' $HACK_INI)
[ "$PRUSA_ENABLE" != "on" ] && exit 0
PRUSA_URL=$(awk -F "=" '/^PRUSA_URL *=/ {print $2}' $HACK_INI)
PRUSA_TOKEN=$(awk -F "=" '/^PRUSA_TOKEN *=/ {print $2}' $HACK_INI)
PRUSA_FINGERPRINT=$(awk -F "=" '/^PRUSA_FINGERPRINT *=/ {print $2}' $HACK_INI)
PRUSA_INTERVAL=$(awk -F "=" '/^PRUSA_INTERVAL *=/ {print $2}' $HACK_INI)
PRUSA_CH=$(awk -F "=" '/^PRUSA_CH *=/ {print $2}' $HACK_INI)
PRUSA_INSECURE=$(awk -F "=" '/^PRUSA_INSECURE *=/ {print $2}' $HACK_INI)
[ "$PRUSA_URL" = "" -o "$PRUSA_TOKEN" = "" ] && exit 0
[ "$PRUSA_INTERVAL" = "" ] && PRUSA_INTERVAL=10
[ "$PRUSA_CH" = "Sub" ] && CH=1 || CH=0
INSECURE=""
[ "$PRUSA_INSECURE" = "on" ] && INSECURE="-k"

# fingerprint must be a persistent unique id (16+ chars); generate once if not set
FP_FILE=/media/mmc/.prusa_fingerprint
if [ "$PRUSA_FINGERPRINT" = "" ]; then
  if [ -f $FP_FILE ]; then
    PRUSA_FINGERPRINT=$(cat $FP_FILE)
  else
    PRUSA_FINGERPRINT="$(hostname)-$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16)"
    echo "$PRUSA_FINGERPRINT" > $FP_FILE
  fi
fi

TMP=/tmp/prusa_snapshot.jpg
mkdir -p /tmp/log

count=0
while : ; do
  res=`/scripts/cmd audio` 2> /dev/null
  [ "$res" = "on" -o "$res" = "off" ] && break
  sleep 2
  let count++
  [ 60 -le $count ] && echo "prusa: libcallback not ready" >> /tmp/log/prusa.log && exit 1
done

while : ; do
  echo "jpeg $CH -n" | /usr/bin/nc localhost 4000 > $TMP 2> /dev/null
  if [ -s $TMP ] && [ "$(head -c 5 $TMP)" != "error" ]; then
    code=$(/usr/bin/curl -X PUT --ipv4 --max-time 10 --silent --show-error \
      --output /dev/null --write-out "%{http_code}" \
      -H "accept: */*" -H "content-type: image/jpg" \
      -H "fingerprint: $PRUSA_FINGERPRINT" -H "token: $PRUSA_TOKEN" \
      --data-binary "@$TMP" $INSECURE "$PRUSA_URL")
    case "$code" in
      2*) sleep $PRUSA_INTERVAL ;;
      *)  echo $(date +"%Y/%m/%d %H:%M:%S") "prusa: upload failed ($code)"; sleep 60 ;;
    esac
  else
    echo $(date +"%Y/%m/%d %H:%M:%S") "prusa: jpeg capture failed"; sleep 30
  fi
done >> /tmp/log/prusa.log 2>&1
