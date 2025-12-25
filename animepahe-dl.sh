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
    if [[ -z ${ANIMEPAHE_DL_NODE:-} ]]; then
        _NODE="$(command -v node)" || command_not_found "node"
    else
        _NODE="$ANIMEPAHE_DL_NODE"
    fi
    _FFMPEG="$(command -v ffmpeg)" || command_not_found "ffmpeg"
    if [[ ${_PARALLEL_JOBS:-} -gt 1 ]]; then
       _OPENSSL="$(command -v openssl)" || command_not_found "openssl"
    fi

    _HOST="https://animepahe.si"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"
    _REFERER_URL="https://kwik.cx/"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
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

get() {
    # $1: url
    "$_CURL" -sS -L "$1" -H "cookie: $_COOKIE" --compressed
}

set_cookie() {
    local u
    u="$(LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 16)"
    _COOKIE="__ddg2_=$u"
}

download_anime_list() {
    get "$_ANIME_URL" \
    | grep "/anime/" \
    | sed -E 's/.*anime\//[/;s/" title="/] /;s/\">.*/   /;s/" title/]/' \
    > "$_ANIME_LIST_FILE"
}

search_anime_by_name() {
    # $1: anime name
    local d n
    d="$(get "$_HOST/api?m=search&q=${1// /%20}")"
    n="$("$_JQ" -r '.total' <<< "$d")"
    if [[ "$n" -eq "0" ]]; then
        echo ""
    else
        "$_JQ" -r '.data[] | "[\(.session)] \(.title)   "' <<< "$d" \
            | tee -a "$_ANIME_LIST_FILE" \
            | remove_slug
    fi
}

get_episode_list() {
    # $1: anime id
    # $2: page number
    get "${_API_URL}?m=release&id=${1}&sort=episode_asc&page=${2}"
}

download_source() {
    local d p n
    mkdir -p "$_SCRIPT_PATH/$_ANIME_NAME"
    d="$(get_episode_list "$_ANIME_SLUG" "1")"
    p="$("$_JQ" -r '.last_page' <<< "$d")"

    if [[ "$p" -gt "1" ]]; then
        for i in $(seq 2 "$p"); do
            n="$(get_episode_list "$_ANIME_SLUG" "$i")"
            d="$(echo "$d $n" | "$_JQ" -s '.[0].data + .[1].data | {data: .}')"
        done
    fi

    echo "$d" > "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE"
}

get_episode_link() {
    # $1: episode number
    local s o l r=""
    s=$("$_JQ" -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .session' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    [[ "$s" == "" ]] && print_warn "Episode $1 not found!" && return
    o="$("$_CURL" --compressed -sSL -H "cookie: $_COOKIE" "${_HOST}/play/${_ANIME_SLUG}/${s}")"
    l="$(grep \<button <<< "$o" \
        | grep data-src \
        | sed -E 's/data-src="/\n/g' \
        | grep 'data-av1="0"')"

    if [[ -n "${_ANIME_AUDIO:-}" ]]; then
        print_info "Select audio language: $_ANIME_AUDIO"
        r="$(grep 'data-audio="'"$_ANIME_AUDIO"'"' <<< "$l")"
        if [[ -z "${r:-}" ]]; then
            print_warn "Selected audio language is not available, fallback to default."
        fi
    fi

    if [[ -n "${_ANIME_RESOLUTION:-}" ]]; then
        print_info "Select video resolution: $_ANIME_RESOLUTION"
        r="$(grep 'data-resolution="'"$_ANIME_RESOLUTION"'"' <<< "${r:-$l}")"
        if [[ -z "${r:-}" ]]; then
            print_warn "Selected video resolution is not available, fallback to default"
        fi
    fi

    if [[ -z "${r:-}" ]]; then
        grep kwik <<< "$l" | tail -1 | grep kwik | awk -F '"' '{print $1}'
    else
        awk -F '" ' '{print $1}' <<< "$r" | tail -1
    fi
}

get_playlist_link() {
    # $1: episode link
    local s l
    s="$("$_CURL" --compressed -sS -H "Referer: $_REFERER_URL" -H "cookie: $_COOKIE" "$1" \
        | grep "<script>eval(" \
        | awk -F 'script>' '{print $2}'\
        | sed -E 's/document/process/g' \
        | sed -E 's/querySelector/exit/g' \
        | sed -E 's/eval\(/console.log\(/g')"

    l="$("$_NODE" -e "$s" \
        | grep 'source=' \
        | sed -E "s/.m3u8';.*/.m3u8/" \
        | sed -E "s/.*const source='//")"

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
    s=$("$_CURL" -k -sS -H "Referer: $_REFERER_URL" -H "cookie: $_COOKIE" -C - "$1" -L -g -o "$2" \
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
        bash -c 'decrypt_file "{}" "$k"' < <(ls "${2}/"*.encrypted)
}

download_episode() {
    # $1: episode number
    local num="$1" l pl v erropt='' extpicky=''
    v="$_SCRIPT_PATH/${_ANIME_NAME}/${num}.mp4"

    l=$(get_episode_link "$num")
    [[ "$l" != *"/"* ]] && print_warn "Wrong download link or episode $1 not found!" && return

    pl=$(get_playlist_link "$l")
    [[ -z "${pl:-}" ]] && print_warn "Missing video list! Skip downloading!" && return

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."

        [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"
        if ffmpeg -h full 2>/dev/null| grep extension_picky >/dev/null; then
            extpicky="-extension_picky 0"
        fi

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

            ! cd "$opath" && print_warn "Cannot change directory to $opath" && return
            "$_FFMPEG" -f concat -safe 0 -i "$fname" -c copy $erropt -y "$v"
            ! cd "$cpath" && print_warn "Cannot change directory to $cpath" && return
            [[ -z "${_DEBUG_MODE:-}" ]] && rm -rf "$opath" || return 0
        else
            "$_FFMPEG" $extpicky -headers "Referer: $_REFERER_URL" -i "$pl" -c copy $erropt -y "$v"
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

remove_slug() {
    awk -F'] ' '{print $2}'
}

get_slug_from_name() {
    # $1: anime name
    grep "] $1" "$_ANIME_LIST_FILE" | tail -1 | remove_brackets
}

main() {
    set_args "$@"
    set_var
    set_cookie

    if [[ -n "${_INPUT_ANIME_NAME:-}" ]]; then
        _ANIME_NAME=$("$_FZF" -1 <<< "$(search_anime_by_name "$_INPUT_ANIME_NAME")")
        _ANIME_SLUG="$(get_slug_from_name "$_ANIME_NAME")"
    else
        download_anime_list
        if [[ -z "${_ANIME_SLUG:-}" ]]; then
            _ANIME_NAME=$("$_FZF" -1 <<< "$(remove_slug < "$_ANIME_LIST_FILE")")
            _ANIME_SLUG="$(get_slug_from_name "$_ANIME_NAME")"
        fi
    fi

    [[ "$_ANIME_SLUG" == "" ]] && print_error "Anime slug not found!"
    _ANIME_NAME="$(grep "$_ANIME_SLUG" "$_ANIME_LIST_FILE" \
        | tail -1 \
        | remove_slug \
        | sed -E 's/[[:space:]]+$//' \
        | sed -E 's/[^[:alnum:] ,\+\-\)\(]/_/g')"

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
