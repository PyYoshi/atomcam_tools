#!/bin/sh

# Upload a snapshot to Prusa Connect Camera API periodically.
# https://connect.prusa3d.com/docs/cameras/camera_communication/

HACK_INI=/tmp/hack.ini

# Read a hack.ini value, keeping '=' inside the value and stripping any CR.
read_ini() {
  awk -v k="$1" '$0 ~ "^"k" *=" {p=index($0,"="); v=substr($0,p+1); gsub(/\r/,"",v); print v; exit}' "$HACK_INI"
}

PRUSA_ENABLE=$(read_ini PRUSA_ENABLE)
[ "$PRUSA_ENABLE" != "on" ] && exit 0
PRUSA_URL=$(read_ini PRUSA_URL)
PRUSA_TOKEN=$(read_ini PRUSA_TOKEN)
PRUSA_FINGERPRINT=$(read_ini PRUSA_FINGERPRINT)
PRUSA_INTERVAL=$(read_ini PRUSA_INTERVAL)
PRUSA_CH=$(read_ini PRUSA_CH)
PRUSA_INSECURE=$(read_ini PRUSA_INSECURE)
[ "$PRUSA_URL" = "" -o "$PRUSA_TOKEN" = "" ] && exit 0

# interval must be a positive integer (WebUI min/max do not guard direct edits)
case "$PRUSA_INTERVAL" in
  ''|*[!0-9]*) PRUSA_INTERVAL=10 ;;
esac
[ "$PRUSA_INTERVAL" -lt 2 ] && PRUSA_INTERVAL=2

[ "$PRUSA_CH" = "Sub" ] && CH=1 || CH=0
INSECURE=""
[ "$PRUSA_INSECURE" = "on" ] && INSECURE="-k"

# fingerprint must be a persistent unique id (16+ chars); generate once if not set
FP_FILE=/media/mmc/.prusa_fingerprint
if [ "$PRUSA_FINGERPRINT" = "" ]; then
  if [ -s $FP_FILE ]; then
    PRUSA_FINGERPRINT=$(cat $FP_FILE)
  else
    PRUSA_FINGERPRINT="$(hostname)-$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-16)"
    echo "$PRUSA_FINGERPRINT" > $FP_FILE 2> /dev/null
  fi
fi
[ "$PRUSA_FINGERPRINT" = "" ] && exit 0

TMP=/tmp/prusa_snapshot.jpg
mkdir -p /tmp/log

count=0
while : ; do
  res=$(/scripts/cmd audio 2> /dev/null)
  [ "$res" = "on" -o "$res" = "off" ] && break
  sleep 2
  count=$((count + 1))
  [ 60 -le $count ] && echo "prusa: libcallback not ready" >> /tmp/log/prusa.log && exit 1
done

while : ; do
  echo "jpeg $CH -n" | /usr/bin/nc -w 10 localhost 4000 > $TMP 2> /dev/null
  # accept only a real JPEG (SOI marker 0xffd8); rejects empty/partial/"error" replies
  soi=$(od -An -tx1 -N2 $TMP 2> /dev/null | tr -d ' ')
  if [ "$soi" = "ffd8" ]; then
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
