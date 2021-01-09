#!/usr/bin/env bash
#
# Download anime from animepahe in terminal
#
#/ Usage:
#/   ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-l] [-r <resolution>]
#/
#/ Options:
#/   -a <name>               anime name
#/   -s <slug>               anime slug, can be found in $_ANIME_LIST_FILE
#/                           ingored when "-a" is enabled
#/   -e <num1,num3-num4...>  optional, episode number to download
#/                           multiple episode numbers seperated by ","
#/                           episode range using "-"
#/   -l                      optional, show m3u8 playlist link without downloading videos
#/   -r                      optional, specify resolution: "1080", "720"...
#/                           by default, the highest resolution is selected
#/   -h | --help             display this help message

set -e
set -u

usage() {
    printf "%b\n" "$(grep '^#/' "$0" | cut -c4-)" && exit 1
}

set_var() {
    _CURL="$(command -v curl)" || command_not_found "curl"
    _JQ="$(command -v jq)" || command_not_found "jq"
    _FZF="$(command -v fzf)" || command_not_found "fzf"
    _NODE="$(command -v node)" || command_not_found "node"
    _FFMPEG="$(command -v ffmpeg)" || command_not_found "ffmpeg"

    _HOST="https://animepahe.com"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"
    _REFERER_URL="https://kwik.cx/"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    while getopts ":hla:s:e:r:" opt; do
        case $opt in
            a)
                _INPUT_ANIME_NAME="$OPTARG"
                ;;
            s)
                _ANIME_SLUG="$OPTARG"
                ;;
            e)
                _ANIME_EPISODE="$OPTARG"
                ;;
            l)
                _LIST_LINK_ONLY=true
                ;;
            r)
                _ANIME_RESOLUTION="$OPTARG"
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
    [[ -z "${_LIST_LINK_ONLY:-}" ]] && printf "%b\n" "\033[32m[INFO]\033[0m $1" >&2
}

print_warn() {
    # $1: warning message
    [[ -z "${_LIST_LINK_ONLY:-}" ]] && printf "%b\n" "\033[33m[WARNING]\033[0m $1" >&2
}

print_error() {
    # $1: error message
    printf "%b\n" "\033[31m[ERROR]\033[0m $1" >&2
    exit 1
}

command_not_found() {
    # $1: command name
    print_error "$1 command not found!"
}

download_anime_list() {
    "$_CURL" --compressed -sS "$_ANIME_URL" \
    | grep "/anime/" \
    | sed -E 's/.*anime\//[/;s/" title="/] /;s/\">.*//' \
    > "$_ANIME_LIST_FILE"
}

search_anime_by_name() {
    # $1: anime name
    local d n
    d="$("$_CURL" --compressed -sS "$_HOST/api?m=search&q=${1// /%20}")"
    n="$("$_JQ" -r '.total' <<< "$d")"
    if [[ "$n" -eq "0" ]] ; then
        echo ""
    else
        "$_JQ" -r '.data[] | "[\(.session)] \(.title)"' <<< "$d" | tee -a "$_ANIME_LIST_FILE"
    fi
}

get_anime_id() {
    # $1: anime slug
    "$_CURL" --compressed -sS "$_ANIME_URL/$1" \
    | grep getJSON \
    | sed -E 's/.*id=//' \
    | awk -F '&' '{print $1}'
}

get_episode_list() {
    # $1: anime id
    # $2: page number
    "$_CURL" --compressed -sS "${_API_URL}?m=release&id=${1}&sort=episode_asc&page=${2}"
}

download_source() {
    local id d p n
    mkdir -p "$_SCRIPT_PATH/$_ANIME_NAME"
    id="$(get_anime_id "$_ANIME_SLUG")"
    d="$(get_episode_list "$id" "1")"
    p="$("$_JQ" -r '.last_page' <<< "$d")"

    if [[ "$p" -gt "1" ]]; then
        for i in $(seq 2 "$p"); do
            n="$(get_episode_list "$id" "$i")"
            d="$(echo "$d $n" | "$_JQ" -s '.[0].data + .[1].data | {data: .}')"
        done
    fi

    echo "$d" > "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE"
}

get_episode_link() {
    # $1: episode number
    local i s d r=""
    i=$("$_JQ" -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .anime_id' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    s=$("$_JQ" -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .session' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    [[ "$i" == "" ]] && print_error "Episode not found!"
    d="$("$_CURL" --compressed -sS "${_API_URL}?m=embed&id=${i}&session=${s}&p=kwik")"

    if [[ -n "${_ANIME_RESOLUTION:-}" ]]; then
        print_info "Select resolution: $_ANIME_RESOLUTION"
        r="$("$_JQ" -r '.data[][$resolution] | select(. != null) | .kwik' \
            --arg resolution "$_ANIME_RESOLUTION" <<< "$d")"
    fi

    if [[ -z "$r" ]]; then
        [[ -n "${_ANIME_RESOLUTION:-}" ]] && \
        print_warn "Selected resolution not available, fallback to default"
        "$_JQ" -r '.data[][].kwik' <<< "$d" | tail -1
    else
        echo "$r"
    fi
}

get_playlist() {
    # $1: episode link
    local s l
    s=$("$_CURL" --compressed -sS -H "Referer: $_REFERER_URL" "$1" \
        | grep '<script>' \
        | sed -E 's/<script>//')

    l=$("$_NODE" -e "$s" 2>&1 \
        | grep 'source=' \
        | sed -E "s/.m3u8';.*/.m3u8/" \
        | sed -E "s/.*const source='//")

    echo "$l"
}

download_episodes() {
    # $1: episode number string
    local origel el uniqel
    origel=()
    if [[ "$1" == *","* ]]; then
        IFS="," read -ra ADDR <<< "$1"
        for n in "${ADDR[@]}"; do
            origel+=("$n")
        done
    else
        origel+=("$1")
    fi

    el=()
    for i in "${origel[@]}"; do
        if [[ "$i" == *"-"* ]]; then
            s=$(awk -F '-' '{print $1}' <<< "$i")
            e=$(awk -F '-' '{print $2}' <<< "$i")
            for n in $(seq "$s" "$e"); do
                el+=("$n")
            done
        else
            el+=("$i")
        fi
    done

    IFS=" " read -ra uniqel <<< "$(printf '%s\n' "${el[@]}" | sort -n -u | tr '\n' ' ')"

    [[ ${#uniqel[@]} == 0 ]] && print_error "Wrong episode number!"

    for e in "${uniqel[@]}"; do
        download_episode "$e"
    done
}

download_episode() {
    # $1: episode number
    local l pl
    l=$(get_episode_link "$1")
    [[ "$l" != *"/"* ]] && print_error "Wrong download link or episode not found!"

    pl=$(get_playlist "$l")
    [[ -z "${pl:-}" ]] && print_error "Missing video list!"

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."
        "$_FFMPEG" -headers "Referer: $_REFERER_URL" -i "$pl" -c copy -v error -y "$_SCRIPT_PATH/${_ANIME_NAME}/${1}.mp4"
    else
        echo "$pl"
    fi
}

select_episodes_to_download() {
    [[ "$(grep 'data' -c "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")" -eq "0" ]] && print_error "No episode available!"
    "$_JQ" -r '.data[] | "[\(.episode | tonumber)] E\(.episode | tonumber) \(.created_at)"' < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" >&2
    echo -n "Which episode(s) to downolad: " >&2
    read -r s
    echo "$s"
}

remove_brackets() {
    awk -F']' '{print $1}' | sed -E 's/^\[//'
}

main() {
    set_args "$@"
    set_var

    if [[ -n "${_INPUT_ANIME_NAME:-}" ]]; then
        _ANIME_SLUG=$("$_FZF" -1 <<< "$(search_anime_by_name "$_INPUT_ANIME_NAME")" | remove_brackets)
    else
        download_anime_list
        if [[ -z "${_ANIME_SLUG:-}" ]]; then
            _ANIME_SLUG=$("$_FZF" < "$_ANIME_LIST_FILE" | remove_brackets)
        fi
    fi

    [[ "$_ANIME_SLUG" == "" ]] && print_error "Anime slug not found!"
    _ANIME_NAME=$(sort -u "$_ANIME_LIST_FILE" \
                | grep "$_ANIME_SLUG" \
                | awk -F '] ' '{print $2}' \
                | sed -E 's/\//_/g' \
                | sed -E 's/\"/_/g' \
                | sed -E 's/\?/_/g' \
                | sed -E 's/\*/_/g' \
                | sed -E 's/\:/_/g')

    [[ "$_ANIME_NAME" == "" ]] && (print_warn "Anime name not found! Try again."; download_anime_list; exit 1)

    download_source

    [[ -z "${_ANIME_EPISODE:-}" ]] && _ANIME_EPISODE=$(select_episodes_to_download)
    download_episodes "$_ANIME_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
