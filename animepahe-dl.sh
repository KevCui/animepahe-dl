#!/usr/bin/env bash
#
# Download anime from animepahe in terminal
#
#/ Usage:
#/   ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-l] [-r <resolution>] [-d]
#/
#/ Options:
#/   -a <name>               anime name
#/   -s <slug>               anime slug, can be found in $_ANIME_LIST_FILE
#/                           ignored when "-a" is enabled
#/   -e <num1,num3-num4...>  optional, episode number to download
#/                           multiple episode numbers seperated by ","
#/                           episode range using "-"
#/                           all episodes using "*"
#/   -l                      optional, show m3u8 playlist link without downloading videos
#/   -r                      optional, specify resolution: "1080", "720"...
#/   -t                      to download episodes faster, specify number of threads
#/                           by default, the highest resolution is selected
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
    if [[ ! -z ${_PARALLEL_JOBS:-} ]]; then
       _XXD="$(command -v xxd)" || command_not_found "xxd"
       _OPENSSL="$(command -v openssl)" || command_not_found "openssl"
    fi

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
    while getopts ":hlda:s:e:r:t:" opt; do
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
                [[ ${_PARALLEL_JOBS} -lt 0 ]] && {
                    print_error "-t switch only takes a positive integer as argument."
                }
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
    if [[ "$n" -eq "0" ]]; then
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
        [[ -n "${_ANIME_RESOLUTION:-}" ]] &&
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
        if [[ "$i" == *"*"* ]]; then
            i="1-$("$_JQ" -r '.data[].episode' "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" \
                | sort -nu \
                | tail -1)"
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

download_episode() {
    # $1: episode number
    local num="$1" l pl erropt=''
    l=$(get_episode_link "$num")
    [[ "$l" != *"/"* ]] && print_error "Wrong download link or episode not found!"

    pl=$(get_playlist "$l")
    [[ -z "${pl:-}" ]] && print_error "Missing video list!"

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."
        [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"
        if [[ ! -z ${_PARALLEL_JOBS:-} ]]; then
            local m3u8_file key_file_url key segments_url total_segments parallel_jobs
            # download m3u8 files
            m3u8_file="$("${_CURL}" -s -H "Referer: $_REFERER_URL" "$pl" 2>&1)" || print_error "${m3u8_file}"

            # grab key from m3u8
            key_file_url="$(grep "#EXT-X-KEY:METHOD" <<< "${m3u8_file}" | sed -e "s/^.*http/http/" -e "s/\"$//")"
            "${_CURL}" -s -H "Referer: $_REFERER_URL" "${key_file_url}" -o "${num}.key_file" || return 1
            key="$("${_XXD}" -p "${num}.key_file")"
            rm -f "${num}.key_file"

            # grab segments
            mapfile -t segments_url <<< "$(grep '^http' <<< "${m3u8_file}")" && total_segments="${#segments_url}"

            mkdir -p "$_SCRIPT_PATH/${_ANIME_NAME}/${num}"
            cd "$_SCRIPT_PATH/${_ANIME_NAME}/${num}/" || exit 1

            # setup for xargs
            parallel_jobs="$((total_segments < _PARALLEL_JOBS ? total_segments : _PARALLEL_JOBS))"
            export _CURL _XXD _OPENSSL _REFERER_URL _SCRIPT_PATH _ANIME_NAME num key

            # download segments parallely
            printf "%s\n" "${segments_url[@]}" | xargs -n 1 -I {} -P "${parallel_jobs}" sh -c '
            url="{}" file="${url##*\/}.encrypted"
            "${_CURL}" -s -H "Referer: $_REFERER_URL" "${url}" -o "${file}"
            ' || return 1

            # decrypt segments parallely
            printf "%b\n" *.ts.encrypted | xargs -n 1 -I {} -P "${parallel_jobs}" sh -c '
            infile="{}" outfile="${infile%%.encrypted}"
            "${_OPENSSL}" aes-128-cbc -d -K "${key}" -iv 0 -nosalt -in "${infile}" -out "${outfile}"
            ' &> /dev/null || return 1

            cd "${_SCRIPT_PATH:?}/${_ANIME_NAME:?}/" || exit 1

            # generate a sorted list with file name format as ffmpeg concat requires
            for i in `ls "${num}/"*.ts | sort -V`; do echo "file $i"; done > "${num}.ffmpeg_file_list"

            # concat all the decrypted ts files
            "$_FFMPEG" $erropt -f concat -i "${num}.ffmpeg_file_list" -c copy -bsf:a aac_adtstoasc -y "${num}.mp4" &&
                rm -rf "${_SCRIPT_PATH:?}/${_ANIME_NAME:?}/${num:?}" &&
                rm -rf "${_SCRIPT_PATH:?}/${_ANIME_NAME:?}/${num:?}.ffmpeg_file_list"
                # remove the ${num} folder and the file list only if ffmpeg command ran successfully
        else
            "$_FFMPEG" -headers "Referer: $_REFERER_URL" -i "$pl" -c copy $erropt -y "$_SCRIPT_PATH/${_ANIME_NAME}/${num}.mp4"
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
    _ANIME_NAME=$(sort -u "$_ANIME_LIST_FILE" \
        | grep "$_ANIME_SLUG" \
        | awk -F '] ' '{print $2}' \
        | sed -E 's/\//_/g' \
        | sed -E 's/\"/_/g' \
        | sed -E 's/\?/_/g' \
        | sed -E 's/\*/_/g' \
        | sed -E 's/\:/_/g')

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
