#!/bin/bash
#
# ---------------------------------------------------------------------------
# bsab - (Binance Spot Assets Balance)
#
# The MIT License (MIT)
#
# Copyright (c) 2021, Marc Vidal De Palol <mvidal.dp@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

# Usage: bsab [[-h|--help]
#        bsab [-i|--investment]]

# Revision history:
# 2020-03-27  Created
# ---------------------------------------------------------------------------

# TODO:
# - order by coin (alphabetically)
# - order by quantity, price, %change or alloc%/value
# - comment whole code
# - include error handling
# - rewrite in functions

PROGNAME="bsab (Binance Spot Assets Balance)"
SCRIPTNAME=${0##*/}
VERSION="1.0"

# Usage message - separate lines for mutually exclusive options
# the way many man pages do it.
usage() {
  printf "%s\n" "Usage: ${SCRIPTNAME} [-h|--help ]"
  printf "%s\n" "         ${SCRIPTNAME} [-i|--investment]"
}

help_message() {
  cat <<-_EOF_
  ${PROGNAME} version ${VERSION}
  Display a Binance account spot assets total balance in real-time.

  $(usage)

  Options:

  -h, --help        Display this help message and exit.
  -i, --investment  Set base investment (e.g. 1000, default=0).

_EOF_
}

case $1 in

-h)
  help_message
  exit
  ;;

--help)
  help_message
  exit
  ;;

-i)
  INVESTMENT=$2
  ;;

--investment)
  INVESTMENT=$2
  ;;

*)
  printf "%s\n" "Unknown option/parameter"
  help_message
  exit
  ;;
esac

APISECRET=$(jq -r .secret keys.json)
APIKEY=$(jq -r .key keys.json)

URL="https://api.binance.com"
SPOT_API="api/v3"

tput civis # hide cursor
stty -echo # hide keyboard input

# color and text styles
PREFIX="\Z"           # indicates style syntax
BOLD="${PREFIX}b"     # add BOLD text style
UBOLD="${PREFIX}B"    # remove BOLD text style
REVERSE="${PREFIX}r"  # REVERSE bg/fg text colors
UREVERSE="${PREFIX}R" # undo bg/fg text colors
# underline="${PREFIX}u" # underline text
# uunderline="${PREFIX}U" # undo underline text
RESET="${PREFIX}n" # RESET style to default/normal
TAB=$(echo -e '\t')
# color keys
cs=(black red green yellow blue magenta cyan white)
declare -A colors # associative array (dict)
# add key-value pairs of color-codes (e.g. colors[black]=0)
for cc in "${!cs[@]}"; do
  ck=${cs[$cc]}
  colors[$ck]="${PREFIX}${cc}"
done

while [[ ${input} != "0" ]]; do

  querystr="timestamp=$((($(date +%s) * 1000)))"
  sig=$(echo -n "$querystr" | openssl dgst -sha256 -hmac "${APISECRET}" | cut -c 10-)
  sig="signature=$sig"

  accountq=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/account?${querystr}&${sig}" | jq '.balances | map(select(.free|tonumber>0)) | map({(.asset): (.free|tonumber)}) | add')

  mapfile -t amounts <<<"$(jq '. | to_entries[].value' <<<"${accountq}")"
  mapfile -t coins <<<"$(jq -r '. | keys_unsorted | .[]' <<<"${accountq}")"

  declare -A assets # associative array (dict)
  # add key-value pairs of coins-amounts
  for i in "${!coins[@]}"; do
    coin=${coins[$i]}
    amount=${amounts[$i]}
    assets[$coin]=$amount
  done

  declare -A prices
  declare -A changes
  for coin in "${!assets[@]}"; do
    symbol="${coin}USDT"
    mapfile -t pricper <<<"$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/ticker/24hr?symbol=${symbol}" | jq '. | [(.lastPrice|tonumber), (.priceChangePercent|tonumber)] | .[]')"
    prices[${coin}]=${pricper[0]}
    changes[${coin}]=${pricper[1]}
  done

  equiv=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/ticker/price?symbol=EURUSDT" | jq '.price|tonumber')

  total=0
  to_print="${REVERSE}${BOLD}COIN${TAB}QTY${TAB}${TAB}PRICE${TAB}${TAB} %24H↑↓${TAB}%ALLOC${TAB}VALUE${TAB}    ${UREVERSE}\n"
  line=""
  for i in {0..65}; do
    line="${line}-"
  done
  to_print="${to_print}${UBOLD}"
  # calculate total
  for coin in "${coins[@]}"; do
    qty=${assets[$coin]}
    value=$(echo "${qty} * ${prices[$coin]} / ${equiv}" | bc -l)
    total=$(echo "${total} + ${value}" | bc -l)
  done
  # prepare values to display
  for coin in "${coins[@]}"; do
    asset="${BOLD}$(printf "%s" "${coin}")${UBOLD}"
    qty=${assets[${coin}]}
    change=${changes[${coin}]}
    if (($(echo "${change} < 0" | bc -l))); then
      changec=red
      sign=""
    else
      changec=green
      sign="+"
    fi
    change="${sign}$(printf "%.2f" "${change}")"
    # fix change padding with spaces
    integers=$(echo "${change}" | cut -d'.' -f1)
    integers=${#integers}
    lack=$((3 - integers))
    for i in $(eval "echo {0..${lack}}"); do
      change=" ${change}"
    done
    price=${prices[$coin]}
    value=$(echo "${qty} * ${price} / ${equiv}" | bc -l)
    perc=$(echo "${value} * 100.0 / ${total}" | bc -l)
    perc=$(printf "%.2f" "${perc}")
    # fix perc padding with spaces
    integers=$(echo "${perc}" | cut -d'.' -f1)
    integers=${#integers}
    lack=$((2 - integers))
    for i in $(eval "echo {0..${lack}}"); do
      perc=" ${perc}"
    done
    # fix qty decimals with spaces
    decimals=$(echo "${qty}" | cut -d'.' -f2)
    decimals=${#decimals}
    lack=$((8 - decimals))
    for i in $(eval "echo {0..${lack}}"); do
      qty="${qty} "
    done
    # fix qty decimals with spaces
    decimals=$(echo "${price}" | cut -d'.' -f2)
    decimals=${#decimals}
    lack=$((8 - decimals))
    for i in $(eval "echo {0..${lack}}"); do
      price="${price} "
    done
    to_print="${to_print}${asset}${TAB}${qty}${TAB}€${price}${TAB}${colors[${changec}]}${change}${colors[black]}${TAB}${perc}${TAB}€$(printf "%.2f" "${value}")\n\n"
  done
  # ternary operator: green if bigger than investment, red otherwise
  (($(echo "${total} > ${INVESTMENT}" | bc -l))) && totalc=green || totalc=red
  to_print="${to_print}${BOLD}${line}\n"
  to_print="${to_print}TOTAL${TAB}${TAB}${TAB}${TAB}${TAB}${TAB}${TAB}${UBOLD}${colors[${totalc}]}€$(printf "%.2f" "${total}")${RESET}"
  height=$((($(awk -F"n" '{print NF-1}' <<<"${to_print}") + 5)))
  clear
  dialog \
    --colors \
    --no-collapse \
    --no-mouse \
    --backtitle "Binance Spot Assets Balance" \
    --title "Total Balance" \
    --ok-label "QUIT" \
    --msgbox "${to_print}" ${height} 0
  input=$?
done

echo # to get a newline after quitting
tput cvvis
stty echo
