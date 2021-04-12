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

# Usage: bsab.sh [OPTIONS]

# Revision history:
# 2020-03-27  Created
# ---------------------------------------------------------------------------

# TODO:
# - comment whole code
# - include error handling
# - rewrite in functions
# - make input read always (for quitting)
# - quit using q/Q/ESC (read keyboard on background)

PROGNAME="bsab (Binance Spot Assets Balance)"
SCRIPTNAME=${0##*/}
VERSION="1.0"

# Usage message - separate lines for mutually exclusive options
# the way many man pages do it.
usage() {
  printf "%s\n" "Usage: ${SCRIPTNAME} [OPTIONS]"
}

help_message() {
  cat <<-_EOF_
  ${PROGNAME} version ${VERSION}
  Display a Binance account spot assets balance in real-time.

  $(usage)

  Options:

  -h, --help        Display this help message and exit.
  -c, --currency    Set currency symbol (e.g. EUR (default), USDT, BTC, ETH).
  -i, --investment  Set base investment (e.g. 1000, default=0).
  -s, --sort        Set column to sort values ([COIN, CHANGE, VALUE, QTY, ALLOC, TOTAL], default=CHANGE).
  -a, --ascending   Set ascending sorting order.
  -d, --descending  Set descending sorting order (default).

_EOF_
}

# default currency, investment values
CURRENCY="EUR"
INVESTMENT=0
SORTBY="CHANGE"
ORDER="DESC"

# OPTIONS="hcioad:-help:-currency:-investment:-order:-asc:-desc:"
OPTIONS=":h: :c: :i: :s: :a :d :-:"
while getopts "${OPTIONS}" opt; do
  case ${opt} in
  -)
    case "${OPTARG}" in
    help)
      help_message
      exit 1
      ;;
    currency)
      CURRENCY="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      ;;
    investment)
      INVESTMENT="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      ;;
    sort)
      SORTBY="${!OPTIND}"
      OPTIND=$((OPTIND + 1))
      ;;
    ascending)
      ORDER="ASC"
      OPTIND=$((OPTIND + 1))
      ;;
    descending)
      ORDER="DESC"
      OPTIND=$((OPTIND + 1))
      ;;
    *)
      printf "%s\n\n" "Invalid option: --${OPTARG}"
      help_message
      exit 1
      ;;
    esac
    ;;
  h)
    help_message
    exit 1
    ;;
  c)
    CURRENCY=${OPTARG}
    ;;
  i)
    INVESTMENT=${OPTARG}
    ;;
  s)
    SORTBY=${OPTARG}
    ;;
  a)
    ORDER="ASC"
    ;;
  d)
    ORDER="DESC"
    ;;
  ?)
    printf "%s\n\n" "Invalid option: -${OPTARG}"
    help_message
    exit 1
    ;;
  esac
done
shift $((OPTIND - 1))

APISECRET=$(jq -r .secret keys.json)
APIKEY=$(jq -r .key keys.json)

BCURRENCY="USDT"

# Binance API URL
B_API="https://api.binance.com"
SPOT_API="/api/v3"
B_URL=${B_API}${SPOT_API}

# CoinGecko API URL
CG_API_URL="https://api.coingecko.com/api/v3"

if [ -t 0 ]; then
  # hide keyboard input and listen to it (non-blocking mode)
  stty -echo -icanon -icrnl time 0 min 0
  tput civis # hide cursor
fi

# color and text styles
PREFIX="\Z"           # indicates style syntax
BOLD="${PREFIX}b"     # add BOLD text style
UBOLD="${PREFIX}B"    # remove BOLD text style
REVERSE="${PREFIX}r"  # REVERSE bg/fg text colors
UREVERSE="${PREFIX}R" # undo bg/fg text colors
# underline="${PREFIX}u" # underline text
# uunderline="${PREFIX}U" # undo underline text
RESET="${PREFIX}n" # RESET style to default/normal
# T=$(echo -e '\t')
T="    "
# color keys
cs=(black red green yellow blue magenta cyan white)
declare -A colors # associative array (dict)
# add key-value pairs of color-codes (e.g. colors[black]=0)
for cc in "${!cs[@]}"; do
  ck=${cs[$cc]}
  colors[$ck]=${PREFIX}${cc}
done

declare -A prev_prices
input=""
while [[ "x${input}" = "x" ]]; do

  if [[ "${CURRENCY}" == "${BCURRENCY}" ]]; then
    equiv=1.0
  else
    querystr="symbol=${CURRENCY}${BCURRENCY}"
    equiv=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${B_URL}/ticker/price?${querystr}" | jq '.price|tonumber')
    equiv=$(printf "%.8f" "${equiv}")
  fi

  datetime=$(date +"%d-%m-%y %H:%M:%S")
  querystr="timestamp=$(($(date +%s) * 1000))"
  sig=$(echo -n "${querystr}" | openssl dgst -sha256 -hmac "${APISECRET}" | cut -c 10-)
  sig="signature=${sig}"
  querystr="${querystr}&${sig}"

  accountq=$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${B_URL}/account?${querystr}" | jq '.balances | map(select(.free|tonumber>0)) | map({(.asset): (.free|tonumber)}) | add')

  mapfile -t amounts <<<"$(jq '. | to_entries[].value' <<<"${accountq}")"
  mapfile -t symbols <<<"$(jq -r '. | keys_unsorted | .[]' <<<"${accountq}")"

  # all CoinGecko coins
  cg_cs=$(curl -s -X GET -H "accept: application/json" "${CG_API_URL}/coins/list?include_platform=false")

  declare -A cg_ids
  for symbol in "${symbols[@]}"; do
    s=${symbol,,}
    id=$(echo "${cg_cs}" | jq -r --arg s "${s}" '.[] | select(.symbol==$s) | .id')
    cg_ids[${symbol}]=${id}
  done

  declare -A coins # associative array (dict)
  declare -A qtys
  qty_max=0
  # add key-value pairs of coins-amounts
  for i in "${!symbols[@]}"; do
    coin=${symbols[${i}]}
    amount=${amounts[${i}]}
    # transform to 8 decimal (also to avoid exponentials)
    amount=$(printf "%.8f" "${amount}")
    max=${#amount}
    if ((max > qty_max)); then
      qty_max=${max}
    fi
    coins[${coin}]=${coin}
    qtys[${coin}]=${amount}
  done

  if [[ "${#prev_prices[@]}" == "0" ]]; then
    unset prev_prices
    declare -A prev_prices
  fi

  ids=$(printf "%s," "${cg_ids[@]}")
  querystr="ids=${ids}&vs_currencies=eur&include_market_cap=true&include_24hr_vol=false&include_24hr_change=false&include_last_updated_at=false"
  cg_mc=$(curl -s -X GET -H "accept: application/json" "${CG_API_URL}/simple/price?${querystr}")
  declare -A mcaps
  mcap_max=0
  for symbol in "${symbols[@]}"; do
    id=${cg_ids[${symbol}]}
    mcap=$(echo "${cg_mc}" | jq -r --arg id "$id" 'to_entries[] | select(.key==$id) | .value.eur_market_cap')
    mcap=$(printf "%'d" "${mcap%%.*}")
    max=${#mcap}
    if ((max > mcap_max)); then
      mcap_max=${max}
    fi
    mcaps[${symbol}]=${mcap}
  done

  # get market cap % for BTC
  mc_btc_perc=$(curl -s -X GET -H "accept: application/json" "${CG_API_URL}/global" | jq '.data.market_cap_percentage.btc')
  mc_btc=$(printf "%s" "${mcaps[BTC]}" | sed 's/,//g')
  declare -A mcaps_perc
  for symbol in "${symbols[@]}"; do
    mcap=$(printf "%s" "${mcaps[${symbol}]}" | sed 's/,//g')
    perc=$(echo "${mcap} * ${mc_btc_perc} / ${mc_btc}" | bc -l)
    perc=$(printf "%.4f" "${perc}")
    mcaps_perc[${symbol}]=${perc}
  done

  declare -A change_7
  declare -A change_14
  declare -A change_30
  declare -A change_60
  declare -A change_200
  declare -A change_year
  declare -A changecs_7
  declare -A changecs_14
  declare -A changecs_30
  declare -A changecs_60
  declare -A changecs_200
  declare -A changecs_year
  week_max=0
  biweek_max=0
  month_max=0
  bimonth_max=0
  hy_max=0
  year_max=0
  for symbol in "${symbols[@]}"; do
    id=${cg_ids[${symbol}]}
    querystr="tickers=false&market_data=true&community_data=false&developer_data=false&sparkline=false"
    mapfile -t chpercs <<<"$(curl -s -X GET -H "accept: application/json" "${CG_API_URL}/coins/${id}?${querystr}" | jq -r '.market_data | [.price_change_percentage_7d, .price_change_percentage_14d, .price_change_percentage_30d, .price_change_percentage_60d, .price_change_percentage_200d, .price_change_percentage_1y] | .[]')"
    # check sign and colors
    ch7=$(printf "%.2f" "${chpercs[0]}")
    if (($(echo "${ch7} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_7[${symbol}]=${color}
    ch7="${sign}${ch7}"
    ch14=$(printf "%.2f" "${chpercs[1]}")
    if (($(echo "${ch14} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_14[${symbol}]=${color}
    ch14="${sign}${ch14}"
    ch30=$(printf "%.2f" "${chpercs[2]}")
    if (($(echo "${ch30} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_30[${symbol}]=${color}
    ch30="${sign}${ch30}"
    ch60=$(printf "%.2f" "${chpercs[3]}")
    if (($(echo "${ch60} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_60[${symbol}]=${color}
    ch60="${sign}${ch60}"
    ch200=$(printf "%.2f" "${chpercs[4]}")
    if (($(echo "${ch200} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_200[${symbol}]=${color}
    ch200="${sign}${ch200}"
    chyear=$(printf "%.2f" "${chpercs[5]}")
    if (($(echo "${chyear} < 0" | bc -l))); then
      color=${colors[red]}
      sign=""
    else
      color=${colors[green]}
      sign="+"
    fi
    changecs_year[${symbol}]=${color}
    chyear="${sign}${chyear}"
    # check lengths
    max=${#ch7}
    if ((max > week_max)); then
      week_max=${max}
    fi
    max=${#ch14}
    if ((max > biweek_max)); then
      biweek_max=${max}
    fi
    max=${#ch30}
    if ((max > month_max)); then
      month_max=${max}
    fi
    max=${#ch60}
    if ((max > bimonth_max)); then
      bimonth_max=${max}
    fi
    max=${#ch200}
    if ((max > hy_max)); then
      hy_max=${max}
    fi
    max=${#chyear}
    if ((max > year_max)); then
      year_max=${max}
    fi
    change_7[${symbol}]=${ch7}
    change_14[${symbol}]=${ch14}
    change_30[${symbol}]=${ch30}
    change_60[${symbol}]=${ch60}
    change_200[${symbol}]=${ch200}
    change_year[${symbol}]=${chyear}
  done

  declare -A prices
  declare -A changes
  declare -A changes_raw
  declare -A changecs
  declare -A pricescs
  price_max=0
  change_max=0

  # TODO: store as gist and remove
  # run curl in parallel tests (too slow, no speed gain):
  # unset "coins[USDT]"
  # njobs=${#coins[@]}
  # njobs=20
  # printf "%s\n" "${coins[@]}" | parallel curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${B_URL}/ticker/24hr?symbol={}${BCURRENCY}"
  # printf "%s\n" "${coins[@]}" | parallel curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${B_URL}/ticker/24hr?symbol={}${BCURRENCY}" | jq '. | [(.lastPrice|tonumber), (.priceChangePercent|tonumber)] | .[]'

  for coin in "${coins[@]}"; do
    # TODO: find out and fix USDT/selected currency 24h change %
    if [[ "${coin}" == "${BCURRENCY}" ]]; then
      price=$(echo "1.0 / ${equiv}" | bc -l)
      symbol=${cg_ids[${coin}]}
      querystr="ids=${symbol}&vs_currencies=usd&include_market_cap=false&include_24hr_vol=false&include_24hr_change=true&include_last_updated_at=false"
      mapfile -t pricper <<<"(${price} $(curl -s -X GET -H "accept: application/json" "${CG_API_URL}/simple/price?${querystr}" | jq -r --arg symbol "$symbol" 'to_entries[] | select(.key==$symbol) | .value.usd_24h_change'))"
    else
      symbol=${coin}${BCURRENCY}
      querystr="symbol=${symbol}"
      mapfile -t pricper <<<"$(curl -s -H "X-MBX-APIKEY: ${APIKEY}" "${B_URL}/ticker/24hr?${querystr}" | jq '. | [(.lastPrice|tonumber), (.priceChangePercent|tonumber)] | .[]')"
      price=$(printf "%.8f" "${pricper[0]}")
      price=$(echo "${price} / ${equiv}" | bc -l)
    fi
    price=$(printf "%.8f" "${price}")
    if [ "${prev_prices["${coin}"]}" ]; then
      prev=${prev_prices[${coin}]}
    else
      prev=0.0
    fi
    if (($(echo "${price} > ${prev}" | bc -l))); then
      colorp=${colors[green]}
    else
      colorp=${colors[red]}
    fi
    unset prev_prices["${coin}"]
    prev_prices[${coin}]=${price}
    change=$(printf "%.2f" "${pricper[1]}")
    if (($(echo "${change} < 0" | bc -l))); then
      colorc=${colors[red]}
      sign=""
    else
      colorc=${colors[green]}
      sign="+"
    fi
    changes_raw[${coin}]=${change}
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
    pricescs[${coin}]=${colorp}
    changecs[${coin}]=${colorc}
    changes[${coin}]=${change}
  done

  total=0
  # calculate total
  for coin in "${coins[@]}"; do
    qty=${qtys[${coin}]}
    value=$(echo "${qty} * ${prices[${coin}]}" | bc -l)
    total=$(echo "${total} + ${value}" | bc -l)
  done

  total_l=$(printf "%.2f" "${total}")
  total_l=${#total_l}

  declare -A percs
  declare -A values
  # calculate allocation (%), format allocation and value
  for coin in "${coins[@]}"; do
    qty=${qtys[${coin}]}
    value=$(echo "${qty} * ${prices[${coin}]}" | bc -l)
    perc=$(echo "${value} * 100.0 / ${total}" | bc -l)
    values[${coin}]=$(printf "%.2f" "${value}")
    percs[${coin}]=$(printf "%.2f" "${perc}")
  done

  # TODO: find out (and fix) why headers need extra space/s
  COIN=$(printf "%-*s" "4" "COIN")
  CHANGE=$(printf "%*s" "${change_max}" "%24H↑↓")
  CHW=$(printf "%*s" "${week_max}" "  %7D↑↓")
  CHBW=$(printf "%*s" "${biweek_max}" " %14D↑↓")
  CHM=$(printf "%*s" "${month_max}" " %30D↑↓")
  CHBM=$(printf "%*s" "${bimonth_max}" "  %2M↑↓")
  CHHY=$(printf "%*s" "${hy_max}" "   %6M↑↓")
  YEAR=$(printf "%*s" "${year_max}" "   %1Y↑↓")
  PRICE=$(printf "%*s" "${price_max}" "${CURRENCY}")
  MCAP=$(printf "%*s" "${mcap_max}" "MCAP")
  MCAPP=$(printf "%*s" "7" "%MCAP")
  QTY=$(printf "%*s" "${qty_max}" "QTY")
  ALLOC=$(printf "%*s" "6" "%ALLOC")
  TOTAL=$(printf "%*s" "${total_l}" "TOTAL")
  header_raw="${COIN}${T}${CHANGE}${T}${CHW}${T}${CHBW}${T}${CHM}${T}${CHBM}${T}${CHHY}${T}${YEAR}${T}${PRICE}${T}${MCAP}${T}${MCAPP}${T}${QTY}${T}${ALLOC}${T}${TOTAL}"
  header="${REVERSE}${BOLD}${header_raw}${UBOLD}${UREVERSE}"
  to_print="${header}\n\n"
  width=${#header_raw}

  # sort by selected column and order (asc/desc)
  sort=""
  declare -A to_sort
  if [[ "${ORDER}" == "DESC" ]]; then
    sort="r"
  fi

  case ${SORTBY} in
  CHANGE)
    for coin in "${!changes_raw[@]}"; do
      to_sort[${coin}]=${changes_raw[${coin}]}
    done
    ;;
  VALUE)
    for coin in "${!prices[@]}"; do
      to_sort[${coin}]=${prices[${coin}]}
    done
    ;;
  QTY)
    for coin in "${!qtys[@]}"; do
      to_sort[${coin}]=${qtys[${coin}]}
    done
    ;;
  ALLOC)
    for coin in "${!percs[@]}"; do
      to_sort[${coin}]=${percs[${coin}]}
    done
    ;;
  TOTAL)
    for coin in "${!values[@]}"; do
      to_sort[${coin}]=${values[${coin}]}
    done
    ;;
  esac

  if [[ "${SORTBY}" == "COIN" ]]; then
    # sort coins by letter
    if [[ "${sort}" == "r" ]]; then
      sort="-${sort}"
    fi
    mapfile -t symbols <<<"$(echo "${symbols[@]}" | tr ' ' '\n' | sort ${sort})"
  else
    IFS=$'\n'
    set -f
    mapfile -t symbols <<<"$(
      for key in "${!to_sort[@]}"; do
        printf '%s:%s\n' "${key}" "${to_sort[${key}]}"
      done | sort -t : -k 2n${sort} | sed 's/:.*//'
    )"
    unset IFS
    set +f
  fi

  # prepare values to display
  for coin in "${symbols[@]}"; do
    # get and add right-justify values
    asset="${BOLD}$(printf "%-*s" "4" "${coin}")${UBOLD}"
    changec=${changecs[${coin}]}
    changec7=${changecs_7[${coin}]}
    changec14=${changecs_14[${coin}]}
    changec30=${changecs_30[${coin}]}
    changec60=${changecs_60[${coin}]}
    changechy=${changecs_200[${coin}]}
    changecy=${changecs_year[${coin}]}
    pricec=${pricescs[${coin}]}
    change=$(printf "%*s" "${change_max}" "${changes[${coin}]}")
    change7=$(printf "%*s" "${week_max}" "${change_7[${coin}]}")
    change14=$(printf "%*s" "${biweek_max}" "${change_14[${coin}]}")
    change30=$(printf "%*s" "${month_max}" "${change_30[${coin}]}")
    change60=$(printf "%*s" "${bimonth_max}" "${change_60[${coin}]}")
    changehy=$(printf "%*s" "${hy_max}" "${change_200[${coin}]}")
    changey=$(printf "%*s" "${year_max}" "${change_year[${coin}]}")
    price=$(printf "%*s" "${price_max}" "${prices[${coin}]}")
    mcap=$(printf "%*s" "${mcap_max}" "${mcaps[${coin}]}")
    mcapp=$(printf "%*s" "7" "${mcaps_perc[${coin}]}")
    qty=$(printf "%*s" "${qty_max}" "${qtys[${coin}]}")
    perc=$(printf "%*s" "6" "${percs[${coin}]}")
    value=$(printf "%*s" "${total_l}" "${values[${coin}]}")
    # fill out row with values
    raw_row="${asset}${T}${change}${T}${change7}${T}${change14}${T}${change30}${T}${change60}${T}${changehy}${T}${changey}${T}${price}${T}${mcap}${T}${mcapp}${T}${qty}${T}${perc}${T}${value}"
    row="${asset}${T}${changec}${change}${RESET}${T}${changec7}${change7}${RESET}${T}${changec14}${change14}${RESET}${T}${changec30}${change30}${RESET}${T}${changec60}${change60}${RESET}${T}${changechy}${changehy}${RESET}${T}${changecy}${changey}${RESET}${T}${pricec}${price}${RESET}${T}${mcap}${T}${mcapp}${T}${qty}${T}${perc}${T}${value}"
    # row=$(echo "${row}" | column -t)
    # get row length, store the longest number of characters
    charnum=${#raw_row}
    if ((charnum > width)); then
      width=${charnum}
    fi
    to_print="${to_print}${row}\n\n"
  done
  width=$((width + 2))
  # build line
  line_l=$((width - 9))
  line=""
  for i in $(eval "echo {0..${line_l}}"); do
    line="${line}-"
  done
  to_print="${to_print}${BOLD}${line}\n"
  # ternary operator: green if bigger than investment, red otherwise
  (($(echo "${total} > ${INVESTMENT}" | bc -l))) && totalc=green || totalc=red
  total=$(printf "%.2f" "${total}")
  last_row="${UBOLD}${colors[${totalc}]}${total}${RESET}"
  last_width=$((width + 1))
  last_row=$(printf "%*s" "${last_width}" "${last_row}")
  to_print="${to_print}${last_row}"

  title="Binance Spot Assets Balance (${CURRENCY}) ${datetime}"
  # height=$(($(awk -F"n" '{print NF-1}' <<<"${to_print}") - 20))
  height=$((${#coins[@]} * 2 + 6))
  clear
  input=$(dd bs=1 count=1 status=none | cat -v)
  dialog \
    --colors \
    --cr-wrap \
    --no-mouse \
    --title "${title}" \
    --infobox "${to_print}" "${height}" "${width}"
done

if [ -t 0 ]; then
  stty sane
  tput cvvis
  exit 0
fi
