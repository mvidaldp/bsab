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
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTILITY,
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
# - quit using q/Q/ESC (read keyboard on background)
# - try curl on multiprocessing
# - fix right margin and line (check diff coins)
# - reading parameters after first one (after $2)

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
  -c, --currency    Set currency symbol (e.g. EUR, BTC, ETH).
  -i, --investment  Set base investment (e.g. 1000, default=0).

_EOF_
}

CURRENCY=EUR
INVESTMENT=1000

case $1 in

-h)
  help_message
  exit
  ;;

--help)
  help_message
  exit
  ;;

-c)
  CURRENCY=$2
  ;;

--currency)
  CURRENCY=$2
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
T=$(echo -e '\t')
# color keys
cs=(black red green yellow blue magenta cyan white)
declare -A colors # associative array (dict)
# add key-value pairs of color-codes (e.g. colors[black]=0)
for cc in "${!cs[@]}"; do
  ck=${cs[$cc]}
  colors[$ck]="${PREFIX}${cc}"
done

while [[ ${input} != "0" ]]; do

  equiv=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/ticker/price?symbol=${CURRENCY}USDT" | jq '.price|tonumber')

  querystr="timestamp=$((($(date +%s) * 1000)))"
  sig=$(echo -n "$querystr" | openssl dgst -sha256 -hmac "${APISECRET}" | cut -c 10-)
  sig="signature=$sig"

  accountq=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/account?${querystr}&${sig}" | jq '.balances | map(select(.free|tonumber>0)) | map({(.asset): (.free|tonumber)}) | add')

  mapfile -t amounts <<<"$(jq '. | to_entries[].value' <<<"${accountq}")"
  mapfile -t coins <<<"$(jq -r '. | keys_unsorted | .[]' <<<"${accountq}")"

  declare -A assets # associative array (dict)
  qty_max=0
  # add key-value pairs of coins-amounts
  for i in "${!coins[@]}"; do
    coin=${coins[$i]}
    amount=${amounts[$i]}
    # transform to 8 decimal (also to avoid exponentials)
    amount=$(printf "%.8f" "${amount}")
    max=${#amount}
    if ((max > qty_max)); then
      qty_max=${max}
    fi
    assets[$coin]=${amount}
  done

  declare -A prices
  declare -A changes
  declare -A changecs
  price_max=0
  change_max=0
  for coin in "${!assets[@]}"; do
    symbol="${coin}USDT"
    mapfile -t pricper <<<"$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${URL}/${SPOT_API}/ticker/24hr?symbol=${symbol}" | jq '. | [(.lastPrice|tonumber), (.priceChangePercent|tonumber)] | .[]')"
    price=$(echo "${pricper[0]} / ${equiv}" | bc -l)
    price=$(printf "%.8f" "${price}")
    change=$(printf "%.2f" "${pricper[1]}")
    if (($(echo "${change} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    change="${sign}${change}"
    max=${#price}
    if ((max > price_max)); then
      price_max=${max}
    fi
    max=${#change}
    if ((max > change_max)); then
      change_max=${max}
    fi
    prices[${coin}]=${price}
    changecs[${coin}]=${color}
    changes[${coin}]=${change}
  done

  total=0
  # calculate total
  for coin in "${coins[@]}"; do
    qty=${assets[$coin]}
    value=$(echo "${qty} * ${prices[$coin]}" | bc -l)
    total=$(echo "${total} + ${value}" | bc -l)
  done

  total_l=$(printf "%.2f" "${total}")
  total_l=${#total_l}

  declare -A percs
  declare -A values
  # calculate allocation (%), format allocation and value
  for coin in "${coins[@]}"; do
    qty=${assets[$coin]}
    value=$(echo "${qty} * ${prices[$coin]}" | bc -l)
    perc=$(echo "${value} * 100.0 / ${total}" | bc -l)
    values[${coin}]=$(printf "%.2f" "${value}")
    percs[${coin}]=$(printf "%.2f" "${perc}")
  done

  COIN_LBL=$(printf "%-*s" "4" "COIN")
  CHANGE_LBL=$(printf "%*s" "${change_max}" "%24H↑↓")
  PRICE_LBL=$(printf "%*s" "${price_max}" "${CURRENCY}")
  QTY_LBL=$(printf "%*s" "${qty_max}" "QTY")
  TOTAL_LBL=$(printf "%*s" "${total_l}" "TOTAL")
  header="${REVERSE}${BOLD}${COIN_LBL}${T}${CHANGE_LBL}${T}${PRICE_LBL}${T}${QTY_LBL}${T}%ALLOC${T}${TOTAL_LBL}${UREVERSE}${UBOLD}\n\n"
  to_print="${header}"

  width=0
  # prepare values to display
  for coin in "${coins[@]}"; do
    # get and add right-justify values
    asset="${BOLD}$(printf "%s" "${coin}")${UBOLD}"
    changec=${changecs[${coin}]}
    change=$(printf "%*s" "${change_max}" "${changes[${coin}]}")
    price=$(printf "%*s" "${price_max}" "${prices[$coin]}")
    qty=$(printf "%*s" "${qty_max}" "${assets[${coin}]}")
    perc=$(printf "%*s" "6" "${percs[${coin}]}")
    value=$(printf "%*s" "${total_l}" "${values[${coin}]}")
    # fill out row with values
    row="${asset}${T}${changec}${change}${RESET}${T}${price}${T}${qty}${T}${perc}${T}${value}"
    # get row length, store the longest number of characters
    charnum=${#row}
    if ((charnum > width)); then
      width=${charnum}
    fi
    to_print="${to_print}${row}\n\n"
  done
  # build line
  line_l=$((width - 5))
  line=""
  for i in $(eval "echo {0..${line_l}}"); do
    line="${line}-"
  done
  to_print="${to_print}${BOLD}${line}\n"
  # ternary operator: green if bigger than investment, red otherwise
  (($(echo "${total} > ${INVESTMENT}" | bc -l))) && totalc=green || totalc=red
  total=$(printf "%.2f" "${total}")
  last_row="${T}${UBOLD}${colors[${totalc}]}${total}${RESET}"
  last_row=$(printf "%*s" "${width}" "${last_row}")
  to_print="${to_print}${last_row}"

  height=$(($(awk -F"n" '{print NF-1}' <<<"${to_print}") - 6))
  width=$((width + 6))
  clear
  dialog \
    --colors \
    --no-collapse \
    --no-mouse \
    --backtitle "Binance Spot Assets Balance" \
    --title "Total Balance" \
    --infobox "${to_print}" "${height}" "${width}"
done

echo # to get a newline after quitting
tput cvvis
stty echo
