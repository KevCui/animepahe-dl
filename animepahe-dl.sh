#!/usr/bin/env bash
#
# Download anime from animepahe using CLI
#
#/ Usage:
#/   ./animepahe-dl.sh [-s <anime_slug>] [-e <episode_num1,num2...>]
#/
#/ Options:
#/   -s <slug>          Anime slug, can be found in $_ANIME_LIST_FILE
#/   -e <num1,num2...>  Optional, episode number to download
#/                      multiple episode numbers seperated by ","
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
    _BYPASS_CF_SCRIPT="$_SCRIPT_PATH/bin/bypasscf.js"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    while getopts ":hs:e:" opt; do
        case $opt in
            s)
                _ANIME_SLUG="$OPTARG"
                ;;
            e)
                _ANIME_EPISODE="$OPTARG"
                ;;
            h)
                usage
                ;;
            \?)
                echo "[ERROR] Invalid option: -$OPTARG" >&2
                usage
                ;;
        esac
    done
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
    local l v cf j t c
    l=$(echo "$1" | sed -E 's/.cx\/e/.cx\/f/')
    v=$($_CHROME --version | awk '{print $2}')
    cf=$(get_cf_clearance "$l")

    if [[ -z "$cf" ]]; then
        echo "[ERROR] Cannot fetch cf_clearance from $l!" >&2 && exit 1
    fi

    h=$($_CURL -sS -c - "$l" \
        --header "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$v Safari/537.36" \
        --header "cookie: cf_clearance=$cf")

    j=$(grep 'eval' <<< "$h" | sed -E 's/^[[:space:]]+eval/console.log/')

    t=$($_NODE -e "$j" 2>&1 \
        | sed -E "s/.*value=\"//" \
        | awk -F'"' '{print $1}')

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

download_source() {
    mkdir -p "$_SCRIPT_PATH/$_ANIME_SLUG"
    $_CURL -sS "${_API_URL}?m=release&id=$(get_anime_id "$_ANIME_SLUG")&sort=episode_asc" > "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE"
}

get_episode_link() {
    # $1: episode number
    local i s
    i=$($_JQ -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .anime_id' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE")
    s=$($_JQ -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .session' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE")
    if [[ "$i" == "" ]]; then
        echo "[ERROR] Episode not found!" >&2 && exit 1
    else
        $_CURL -sS "${_API_URL}?m=embed&id=${i}&session=${s}&p=kwik" \
            | $_JQ -r '.data[][].url' \
            | tail -1
    fi
}

get_media_link() {
    # $1: episode link
    # $2: token
    # $3: cookie
    local l
    l=$(echo "$1" | sed -E 's/.cx\/e/.cx\/d/')
    $_CURL -sS "$l" \
        -H "Referer: $l" \
        -H "Cookie: kwik_session=$3" \
        --data "_token=$2" \
        | $_PUP 'a attr{href}'
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
    $_NODE $_BYPASS_CF_SCRIPT "$_CHROME" 0 "$1" \
        | $_JQ -r '.[] | select(.name == "cf_clearance") | .value'
}

download_episode() {
    # $1: episode number
    local l s t c

    l=$(get_episode_link "$1")
    if [[ "$l" != *"/"* ]]; then
        echo "[ERROR] Wrong download link or episode not found!" >&2 && exit 1
    fi

    s=$(get_token_and_cookie "$l")
    t=$(echo "$s" | awk '{print $1}')
    c=$(echo "$s" | awk '{print $NF}')

    echo "[INFO] Downloading Episode $1..."
    $_CURL -L -g -o "$_SCRIPT_PATH/$_ANIME_SLUG/${_ANIME_SLUG}-${1}.mp4" "$(get_media_link "$l" "$t" "$c")"
}

select_episodes_to_download() {
    $_JQ -r '.data[] | "[\(.episode | tonumber)] E\(.episode | tonumber) \(.created_at)"' < "$_SCRIPT_PATH/$_ANIME_SLUG/$_SOURCE_FILE" >&2
    echo -n "Which episode(s) to downolad: " >&2
    read -r s
    echo "$s"
}

main() {
    set_args "$@"
    set_var

    if [[ -z "${_ANIME_SLUG:-}" ]]; then
        download_anime_list
        if [[ ! -f "$_ANIME_LIST_FILE" ]]; then
            echo "[ERROR] $_ANIME_LIST_FILE not found!" && exit 1
        fi
        _ANIME_SLUG=$($_FZF < "$_ANIME_LIST_FILE" | awk -F']' '{print $1}' | sed -E 's/^\[//')

        if [[ "$_ANIME_SLUG" == "" ]]; then
            exit 0
        fi
    fi

    download_source

    if [[ -z "${_ANIME_EPISODE:-}" ]]; then
        _ANIME_EPISODE=$(select_episodes_to_download)
    fi
    download_episodes "$_ANIME_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
