#!/usr/bin/env bash
#
# Download anime from animepahe using CLI
#
#/ Usage:
#/   ./animepahe-dl.sh [-s <anime_slug>] [-e <episode_num1,num2...>] [-l]
#/
#/ Options:
#/   -s <slug>          Anime slug, can be found in $_ANIME_LIST_FILE
#/   -e <num1,num2...>  Optional, episode number to download
#/                      multiple episode numbers seperated by ","
#/   -l                 Optional, list video link only without downloading
#/   -h | --help        Display this help message

set -e
set -u

usage() {
    printf "%b\n" "$(grep '^#/' "$0" | cut -c4-)" && exit 1
}

set_var() {
    _CURL=$(command -v curl)
    _JQ=$(command -v jq)
    _PUP=$(command -v pup)
    _FZF=$(command -v fzf)
    _NODE=$(command -v node)
    _CHROME=$(command -v chromium)

    _HOST="https://animepahe.com"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"

    _SCRIPT_PATH=$(dirname "$0")
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _BYPASS_CF_SCRIPT="$_SCRIPT_PATH/bin/getCFcookie.js"
    _USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$($_CHROME --version | awk '{print $2}') Safari/537.36"
    _CF_FILE="$_SCRIPT_PATH/cf_clearance"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    while getopts ":hls:e:" opt; do
        case $opt in
            s)
                _ANIME_SLUG="$OPTARG"
                ;;
            e)
                _ANIME_EPISODE="$OPTARG"
                ;;
            l)
                _LIST_LINK_ONLY=true
                ;;
            h)
                usage
                ;;
            \?)
                print_error "Invalid option: -$OPTARG"
                ;;
        esac
    done
}

print_info() {
    # $1: info message
    printf "%b\n" "\033[32m[INFO]\033[0m $1" >&2
}

print_warn() {
    # $1: warning message
    printf "%b\n" "\033[33m[WARNING]\033[0m $1" >&2
}

print_error() {
    # $1: error message
    printf "%b\n" "\033[31m[ERROR]\033[0m $1" >&2
    exit 1
}

download_anime_list() {
    $_CURL -sS "$_ANIME_URL" \
        | $_PUP 'div a' \
        | grep "/anime/" \
        | sed -E 's/.*anime\//[/;s/" title="/] /;s/\">//' \
        > "$_ANIME_LIST_FILE"
}

get_token_and_cookie() {
    # $1: download link
    local l cf j t c

    l=$(sed -E 's/.cx\/e/.cx\/f/' <<< "$1")

    if [[ "$(is_cf_expired)" == "yes" ]]; then
        cf=$(get_cf_clearance "$l" | tee "$_CF_FILE")
    else
        cf=$(cat "$_CF_FILE")
    fi

    [[ -z "$cf" ]] && print_error "Cannot fetch cf_clearance from $l!"

    h=$($_CURL -sS -c - "$l" \
        --header "User-Agent: $_USER_AGENT"  \
        --header "cookie: cf_clearance=$cf")

    j=$(grep 'decodeURIComponent' <<< "$h" | grep 'escape' | sed -E 's/return decodeURIComponent/return console.log/')

    t=$($_NODE -e "$j" 2>&1 \
        | grep '_token' \
        | sed -E 's/.*_token%22%20value%3D%22//' \
        | awk -F '%22' '{print $1}')

    c=$(grep '_session' <<< "$h" | awk '{print $NF}')

    echo "$t $c"
}

get_anime_id() {
    # $1: anime slug
    $_CURL -sS "$_ANIME_URL/$1" \
        | grep getJSON \
        | sed -E 's/.*id=//' \
        | awk -F '&' '{print $1}'
}

get_episode_list() {
    # $1: anime id
    # $2: page number
    $_CURL -sS "${_API_URL}?m=release&id=${1}&sort=episode_asc&page=${2}"
}

download_source() {
    local id d p n
    mkdir -p "$_SCRIPT_PATH/$_ANIME_NAME"
    id="$(get_anime_id "$_ANIME_SLUG")"
    d="$(get_episode_list "$id" "1")"
    p="$($_JQ -r '.last_page' <<< "$d")"

    if [[ "$p" -gt "1" ]]; then
        for i in $(seq 2 "$p"); do
            n="$(get_episode_list "$id" "$i")"
            d="$(echo "$d $n" | $_JQ -s '.[0].data + .[1].data | {data: .}')"
        done
    fi

    echo "$d" > "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE"
}

get_episode_link() {
    # $1: episode number
    local i s
    i=$($_JQ -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .anime_id' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    s=$($_JQ -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .session' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    [[ "$i" == "" ]] && print_error "Episode not found!"
    $_CURL -sS "${_API_URL}?m=embed&id=${i}&session=${s}&p=kwik" \
        | $_JQ -r '.data[][].kwik' \
        | tail -1
}

download_episodes() {
    # $1: episode number string
    if [[ "$1" == *","* ]]; then
        IFS=","
        read -ra ADDR <<< "$1"
        for e in "${ADDR[@]}"; do
            download_episode "$e"
        done
    else
        download_episode "$1"
    fi
}

get_cf_clearance() {
    # $1: url
    print_info "Wait for solving reCAPTCHA to visit $1..."
    $_BYPASS_CF_SCRIPT -u "$1" -a "$_USER_AGENT" -p "$_CHROME" -s \
        | $_JQ -r '.[] | select(.name == "cf_clearance") | .value'
}

is_cf_expired() {
    local o
    o="yes"

    if [[ -f "$_CF_FILE" && -s "$_CF_FILE" ]]; then
        local d n
        d=$(date -d "$(date -r "$_CF_FILE") +1 days" +%s)
        n=$(date +%s)

        if [[ "$n" -lt "$d" ]]; then
            o="no"
        fi
    fi

    echo "$o"
}

download_episode() {
    # $1: episode number
    local l s t c ol rl

    l=$(get_episode_link "$1")
    [[ "$l" != *"/"* ]] && print_error "Wrong download link or episode not found!"

    s=$(get_token_and_cookie "$l")
    t=$(echo "$s" | awk '{print $1}')
    c=$(echo "$s" | awk '{print $NF}')

    ol=$(sed -E 's/.cx\/e/.cx\/d/' <<< "$l")
    rl=$(sed -E 's/.cx\/e/.cx\/f/' <<< "$l")
    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."
        $_CURL -L "$ol" \
            -H "Referer: $rl" \
            -H "Cookie: kwik_session=$c" \
            --data "_token=$t" -g -o "$_SCRIPT_PATH/${_ANIME_NAME}/${1}.mp4"
    else
        $_CURL -sSD - "$ol" \
            -H "Referer: $rl" \
            -H "Cookie: kwik_session=$c" \
            --data "_token=$t" \
        | grep "location:" \
        | tr -d '\r' \
        | awk -F ': ' '{print $2}'
    fi
}

select_episodes_to_download() {
    $_JQ -r '.data[] | "[\(.episode | tonumber)] E\(.episode | tonumber) \(.created_at)"' < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" >&2
    echo -n "Which episode(s) to downolad: " >&2
    read -r s
    echo "$s"
}

main() {
    set_args "$@"
    set_var

    if [[ -z "${_ANIME_SLUG:-}" ]]; then
        download_anime_list
        [[ ! -s "$_ANIME_LIST_FILE" ]] && print_error "$_ANIME_LIST_FILE not found!"
        _ANIME_SLUG=$($_FZF < "$_ANIME_LIST_FILE" | awk -F']' '{print $1}' | sed -E 's/^\[//')
    fi

    [[ "$_ANIME_SLUG" == "" ]] && print_error "Anime slug not found!"
    _ANIME_NAME=$(grep "$_ANIME_SLUG" "$_ANIME_LIST_FILE" | awk -F '] ' '{print $2}' | sed -E 's/\//_/g')

    [[ "$_ANIME_NAME" == "" ]] && (print_warn "Anime name not found! Try again."; download_anime_list; exit 1)

    download_source

    [[ -z "${_ANIME_EPISODE:-}" ]] && _ANIME_EPISODE=$(select_episodes_to_download)
    download_episodes "$_ANIME_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
