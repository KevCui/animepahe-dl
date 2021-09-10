#!/usr/bin/env bash
#
# Download anime from animepahe in terminal
#
#/ Usage:
#/   ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-r <resolution>] [-t <num>] [-l] [-d]
#/
#/ Options:
#/   -a <name>               anime name
#/   -s <slug>               anime slug/uuid, can be found in $_ANIME_LIST_FILE
#/                           ignored when "-a" is enabled
#/   -e <num1,num3-num4...>  optional, episode number to download
#/                           multiple episode numbers seperated by ","
#/                           episode range using "-"
#/                           all episodes using "*"
#/   -r <resolution>         optional, specify resolution: "1080", "720"...
#/                           by default, the highest resolution is selected
#/   -o <language>           optional, specify audio language: "eng", "jpn"...
#/   -t <num>                optional, specify a positive integer as num of threads
#/   -l                      optional, show m3u8 playlist link without downloading videos
#/   -d                      enable debug mode
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
    if [[ ${_PARALLEL_JOBS:-} -gt 1 ]]; then
       _OPENSSL="$(command -v openssl)" || command_not_found "openssl"
    fi

    _HOST="https://animepahe.com"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"
    _REFERER_URL="https://kwik.cx/"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
    _COOKIE="__ddg2="
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    _PARALLEL_JOBS=1
    while getopts ":hlda:s:e:r:t:o:" opt; do
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
            t)
                _PARALLEL_JOBS="$OPTARG"
                if [[ ! "$_PARALLEL_JOBS" =~ ^[0-9]+$ || "$_PARALLEL_JOBS" -eq 0 ]]; then
                    print_error "-t <num>: Number must be a positive integer"
                fi
                ;;
            o)
                _ANIME_AUDIO="$OPTARG"
                ;;
            d)
                _DEBUG_MODE=true
                set -x
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
    "$_CURL" --compressed -sS "$_ANIME_URL" -H "Cookie: $_COOKIE" \
    | grep "/anime/" \
    | sed -E 's/.*anime\//[/;s/" title="/] /;s/\">.*//' \
    > "$_ANIME_LIST_FILE"
}

search_anime_by_name() {
    # $1: anime name
    local d n
    d="$("$_CURL" --compressed -sS "$_HOST/api?m=search&q=${1// /%20}" -H "Cookie: $_COOKIE")"
    n="$("$_JQ" -r '.total' <<< "$d")"
    if [[ "$n" -eq "0" ]]; then
        echo ""
    else
        "$_JQ" -r '.data[] | "[\(.session)] \(.title)"' <<< "$d" | tee -a "$_ANIME_LIST_FILE"
    fi
}

get_anime_id() {
    # $1: anime slug
    "$_CURL" --compressed -sS -L "$_ANIME_URL/$1" -H "Cookie: $_COOKIE" \
    | grep getJSON \
    | sed -E 's/.*id=//' \
    | awk -F '&' '{print $1}'
}

get_episode_list() {
    # $1: anime id
    # $2: page number
    "$_CURL" --compressed -sS "${_API_URL}?m=release&id=${1}&sort=episode_asc&page=${2}" -H "Cookie: $_COOKIE"
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
    d="$("$_CURL" --compressed -sS "${_API_URL}?m=embed&id=${i}&session=${s}&p=kwik" -H "Cookie: $_COOKIE" \
        | "$_JQ" -r '.data[]')"

    if [[ -n "${_ANIME_AUDIO:-}" ]]; then
        print_info "Select audio language: $_ANIME_AUDIO"
        r="$("$_JQ" -r '.[] |= select(.audio == "'"$_ANIME_AUDIO"'") | select(.[] != null)' <<< "$d")"
        if [[ -n "${r:-}" ]]; then
            d="$r"
        else
            print_warn "Selected audio language is not available, fallback to default."
        fi
    fi

    if [[ -n "${_ANIME_RESOLUTION:-}" ]]; then
        print_info "Select video resolution: $_ANIME_RESOLUTION"
        r="$("$_JQ" -r 'to_entries | .[] |= select(.key == "'"$_ANIME_RESOLUTION"'") | from_entries | select(.[] != null)' <<< "$d")"
        if [[ -n "${r:-}" ]]; then
            d="$r"
        else
            print_warn "Selected video resolution is not available, fallback to default"
        fi
    fi

    "$_JQ" -r '.[].kwik' <<< "$d" | tail -1
}

get_playlist_link() {
    # $1: episode link
    local s l
    s=$("$_CURL" --compressed -sS -H "Referer: $_REFERER_URL" "$1" \
        | grep '<script>' \
        | grep 'eval(function' \
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
        if [[ "$i" == *"*"* ]]; then
            local eps fst lst
            eps="$("$_JQ" -r '.data[].episode' "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" | sort -nu)"
            fst="$(head -1 <<< "$eps")"
            lst="$(tail -1 <<< "$eps")"
            i="${fst}-${lst}"
        fi

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

get_thread_number() {
    # $1: playlist file
    local sn
    sn="$(grep -c "^https" "$1")"
    if [[ "$sn" -lt "$_PARALLEL_JOBS" ]]; then
        echo "$sn"
    else
        echo "$_PARALLEL_JOBS"
    fi
}

download_file() {
    # $1: URL link
    # $2: output file
    local s
    s=$("$_CURL" -sS -H "Referer: $_REFERER_URL" -C - "$1" -L -g -o "$2" \
        --connect-timeout 5 \
        --compressed \
        || echo "$?")
    if [[ "$s" -ne 0 ]]; then
        print_warn "Download was aborted. Retry..."
        download_file "$1" "$2"
    fi
}

decrypt_file() {
    # $1: input file
    # $2: encryption key in hex
    local of=${1%%.encrypted}
    "$_OPENSSL" aes-128-cbc -d -K "$2" -iv 0 -in "${1}" -out "${of}" 2>/dev/null
}

download_segments() {
    # $1: playlist file
    # $2: output path
    local op="$2"
    export _CURL _REFERER_URL op
    export -f download_file print_warn
    xargs -I {} -P "$(get_thread_number "$1")" \
        bash -c 'url="{}"; file="${url##*/}.encrypted"; download_file "$url" "${op}/${file}"' < <(grep "^https" "$1")
}

generate_filelist() {
    # $1: playlist file
    # $2: output file
    grep "^https" "$1" \
        | sed -E "s/https.*\//file '/" \
        | sed -E "s/$/'/" \
        > "$2"
}

decrypt_segments() {
    # $1: playlist file
    # $2: segment path
    local kf kl k
    kf="${2}/mon.key"
    kl=$(grep "#EXT-X-KEY:METHOD=" "$1" | awk -F '"' '{print $2}')
    download_file "$kl" "$kf"
    k="$(od -A n -t x1 "$kf" | tr -d ' \n')"

    export _OPENSSL k
    export -f decrypt_file
    xargs -I {} -P "$(get_thread_number "$1")" \
        bash -c 'decrypt_file "{}" "$k"' < <(ls "${2}/"*.ts.encrypted \
        | sed -E 's/ /\\ /g')
}

download_episode() {
    # $1: episode number
    local num="$1" l pl erropt='' v
    v="$_SCRIPT_PATH/${_ANIME_NAME}/${num}.mp4"

    l=$(get_episode_link "$num")
    [[ "$l" != *"/"* ]] && print_error "Wrong download link or episode not found!"

    pl=$(get_playlist_link "$l")
    [[ -z "${pl:-}" ]] && print_error "Missing video list!"

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."
        [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"
        if [[ ${_PARALLEL_JOBS:-} -gt 1 ]]; then
            local opath plist cpath fname
            fname="file.list"
            cpath="$(pwd)"
            opath="$_SCRIPT_PATH/$_ANIME_NAME/${num}"
            plist="${opath}/playlist.m3u8"
            rm -rf "$opath"
            mkdir -p "$opath"

            download_file "$pl" "$plist"
            print_info "Start parallel jobs with $(get_thread_number "$plist") threads"
            download_segments "$plist" "$opath"
            decrypt_segments "$plist" "$opath"
            generate_filelist "$plist" "${opath}/$fname"

            cd "$opath" || print_error "Cannot change directory to $opath"
            "$_FFMPEG" -f concat -safe 0 -i "$fname" -c copy $erropt -y "$v"
            cd "$cpath" || print_error "Cannot change directory to $cpath"
            [[ -z "${_DEBUG_MODE:-}" ]] && rm -rf "$opath" || return 0
        else
            "$_FFMPEG" -headers "Referer: $_REFERER_URL" -i "$pl" -c copy $erropt -y "$v"
        fi
    else
        echo "$pl"
    fi
}

select_episodes_to_download() {
    [[ "$(grep 'data' -c "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")" -eq "0" ]] && print_error "No episode available!"
    "$_JQ" -r '.data[] | "[\(.episode | tonumber)] E\(.episode | tonumber) \(.created_at)"' "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" >&2
    echo -n "Which episode(s) to download: " >&2
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
    _ANIME_NAME=$(grep "$_ANIME_SLUG" "$_ANIME_LIST_FILE" \
        | tail -1 \
        | awk -F '] ' '{print $2}' \
        | sed -E 's/[^[:alnum:] .,\+\-\)\(]/_/g')

    if [[ "$_ANIME_NAME" == "" ]]; then
        print_warn "Anime name not found! Try again."
        download_anime_list
        exit 1
    fi

    download_source

    [[ -z "${_ANIME_EPISODE:-}" ]] && _ANIME_EPISODE=$(select_episodes_to_download)
    download_episodes "$_ANIME_EPISODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
