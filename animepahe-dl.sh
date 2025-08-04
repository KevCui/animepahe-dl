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
    _WGET="$(command -v wget)" || command_not_found "wget"
    _JQ="$(command -v jq)" || command_not_found "jq"
    _FZF="$(command -v fzf)" || command_not_found "fzf"
    if [[ -z ${ANIMEPAHE_DL_NODE:-} ]]; then
        _NODE="$(command -v node)" || command_not_found "node"
    else
        _NODE="$ANIMEPAHE_DL_NODE"
    fi
    _FFMPEG="$(command -v ffmpeg)" || command_not_found "ffmpeg"
    _ARIA2="$(command -v aria2c)" || command_not_found "aria2c"
    if [[ ${_PARALLEL_JOBS:-} -gt 1 ]]; then
       _OPENSSL="$(command -v openssl)" || command_not_found "openssl"
    fi

    _HOST="https://animepahe.ru"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"
    _REFERER_URL="$_HOST"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    _PARALLEL_JOBS=32
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
    "$_WGET" -qO- --header="cookie: $_COOKIE" "$1"
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
    local json_file="$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE"
    mkdir -p "$_SCRIPT_PATH/$_ANIME_NAME"
    
    # Only download if cache is missing or invalid
    if [[ ! -s "$json_file" ]] || ! "$_JQ" -e '.data' "$json_file" >/dev/null; then
        print_info "Downloading episode list..."
        local d p n
        d="$(get_episode_list "$_ANIME_SLUG" "1")"
        p="$("$_JQ" -r '.last_page' <<< "$d")"

        if [[ "$p" -gt "1" ]]; then
            for i in $(seq 2 "$p"); do
                n="$(get_episode_list "$_ANIME_SLUG" "$i")"
                d="$(echo "$d $n" | "$_JQ" -s '.[0].data + .[1].data | {data: .}')"
            done
        fi

        echo "$d" > "$json_file"
    else
        print_info "Using cached episode list"
    fi
    
    # Show episode list in terminal - MODIFIED HERE
    print_info "Available episodes:"
    "$_JQ" -r '.data[].episode | tonumber' "$json_file" | sort -nu | awk '{print "  Episode " $1}' >&2
}

get_episode_link() {
    # $1: episode number
    local s o l r=""
    s=$("$_JQ" -r '.data[] | select((.episode | tonumber) == ($num | tonumber)) | .session' --arg num "$1" < "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE")
    [[ "$s" == "" ]] && print_warn "Episode $1 not found!" && return
    o="$("$_WGET" -qO- --header="cookie: $_COOKIE" --header="Referer: $_REFERER_URL" "${_HOST}/play/${_ANIME_SLUG}/${s}")"
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
    s="$("$_WGET" -qO- --header="Referer: $_REFERER_URL" --header="cookie: $_COOKIE" "$1" \
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
    if [[ ! -f "$_SCRIPT_PATH/$_ANIME_NAME/$_SOURCE_FILE" ]]; then
        download_source
    fi
    
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
        # Add error handling to continue with next episode if one fails
        if ! download_episode "$e"; then
            print_warn "Failed to download episode $e, continuing with next..."
            continue
        fi
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
    local url="$1"
    local output_file="$2"
    local output_dir
    output_dir="$(dirname "$output_file")"
    local filename
    filename="$(basename "$output_file")"

    local aria2_opts=(
    --quiet=true
    --allow-overwrite=true
    --auto-file-renaming=false
    --continue=true
    --max-tries=0
    --retry-wait=1
    --timeout=60
    --min-split-size=1M
    --split=32
    --max-connection-per-server=16
    --enable-http-pipelining=true
    --optimize-concurrent-downloads=true
    --reuse-uri=true
    --http-accept-gzip=true
    --max-download-limit=10485760  # 10MB/s in bytes
    --dir "$output_dir"
    -o "$filename"
    --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    --referer="$_REFERER_URL"
    --header="cookie: $_COOKIE"
)

    if [[ ${_PARALLEL_JOBS:-} -gt 1 ]]; then
        aria2_opts+=(
            --enable-http-pipelining=true
        )
    fi

    if ! "$_ARIA2" "${aria2_opts[@]}" "$url"; then
        print_warn "aria2c download failed for $output_file. Retrying..."
        download_file "$url" "$output_file"
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
    local plist="$1"
    export _CURL _REFERER_URL op _ARIA2

    mkdir -p "$op"
    local urls
    mapfile -t urls < <(grep "^https" "$plist")
    local total_segments=${#urls[@]}
    local done_file="${op}/.done-segments.txt"
    : > "$done_file"  # create/empty the file

    export done_file
    export -f download_file print_warn

    # Background progress bar
    (
        while true; do
            local done_count
            done_count=$(wc -l < "$done_file")
            local percent=$((done_count * 100 / total_segments))
            local bar_length=30
            local filled=$((percent * bar_length / 100))
            local empty=$((bar_length - filled))
            local bar="$(printf '#%.0s' $(seq 1 $filled))$(printf '.%.0s' $(seq 1 $empty))"
            printf "\rProgress [%s] (%d/%d)" "$bar" "$done_count" "$total_segments"
            [[ $done_count -ge $total_segments ]] && break
            sleep 0.5
        done
        echo ""
    ) &

    local progress_pid=$!

    printf "%s\n" "${urls[@]}" | \
    xargs -I {} -P "$(get_thread_number "$plist")" \
        bash -c 'url="{}"; file="${url##*/}.encrypted"; download_file "$url" "${op}/${file}" && echo "$file" >> "$done_file"'

    wait "$progress_pid"
    rm -f "$done_file"
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

    local files
    mapfile -t files < <(ls "${2}/"*.encrypted 2>/dev/null)
    local total_segments=${#files[@]}
    [[ $total_segments -eq 0 ]] && print_warn "No segments to decrypt!" && return

    local done_file="${2}/.done-decrypt.txt"
    : > "$done_file"

    export _OPENSSL k done_file
    export -f decrypt_file

    # Background decryption progress bar
    (
        while true; do
            local done_count
            done_count=$(wc -l < "$done_file")
            local percent=$((done_count * 100 / total_segments))
            local bar_length=30
            local filled=$((percent * bar_length / 100))
            local empty=$((bar_length - filled))
            local bar="$(printf '#%.0s' $(seq 1 $filled))$(printf '.%.0s' $(seq 1 $empty))"
            printf "\rDecrypting [%s] (%d/%d)" "$bar" "$done_count" "$total_segments"
            [[ $done_count -ge $total_segments ]] && break
            sleep 0.5
        done
        echo ""
    ) &

    local progress_pid=$!

    printf "%s\n" "${files[@]}" | \
    xargs -I {} -P "$(get_thread_number "$1")" \
        bash -c 'decrypt_file "{}" "$k" && echo "{}" >> "$done_file"'

    wait "$progress_pid"
    rm -f "$done_file"
}

download_episode() {
    # $1: episode number
    local num="$1" l pl v erropt='' extpicky=''
    v="$_SCRIPT_PATH/${_ANIME_NAME}/${num}.mp4"

    # Skip if file already exists
    if [[ -f "$v" ]]; then
        print_info "Episode $1 already exists, skipping..."
        return 0
    fi

    l=$(get_episode_link "$num")
    [[ "$l" != *"/"* ]] && print_warn "Wrong download link or episode $1 not found!" && return 1

    pl=$(get_playlist_link "$l")
    [[ -z "${pl:-}" ]] && print_warn "Missing video list! Skip downloading!" && return 1

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        print_info "Downloading Episode $1..."

        [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"
        if ffmpeg -h full 2>/dev/null | grep extension_picky >/dev/null; then
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

            if ! download_file "$pl" "$plist"; then
                print_warn "Failed to download playlist for episode $1"
                return 1
            fi

            print_info "Start parallel jobs with $(get_thread_number "$plist") threads"

            if ! download_segments "$plist" "$opath"; then
                print_warn "Failed to download segments for episode $1"
                return 1
            fi

            if ! decrypt_segments "$plist" "$opath"; then
                print_warn "Failed to decrypt segments for episode $1"
                return 1
            fi

            generate_filelist "$plist" "${opath}/$fname"

            ! cd "$opath" && print_warn "Cannot change directory to $opath" && return 1

            # Simulated merging progress bar (single-line, no text before)
            (
                local bar_length=30
                local steps=20
                local delay=0.2
                for ((i = 1; i <= steps; i++)); do
                    local filled=$((i * bar_length / steps))
                    local empty=$((bar_length - filled))
                    local bar
                    bar="$(printf '#%.0s' $(seq 1 $filled))$(printf '.%.0s' $(seq 1 $empty))"
                    printf "\rMerging    [%s] (%d%%)" "$bar" $((i * 100 / steps))
                    sleep "$delay"
                done
            ) &

            local progress_pid=$!

            if ! "$_FFMPEG" -f concat -safe 0 -i "$fname" -c copy $erropt -y -threads 0 "$v"; then
                kill "$progress_pid" &>/dev/null
                print_warn "Failed to merge segments for episode $1"
                return 1
            fi

            kill "$progress_pid" &>/dev/null
            wait "$progress_pid" 2>/dev/null || true
            printf "\rMerging    [##############################] (100%%) Done.\n"

            ! cd "$cpath" && print_warn "Cannot change directory to $cpath" && return 1
            [[ -z "${_DEBUG_MODE:-}" ]] && rm -rf "$opath" || return 0
        else
            if ! "$_FFMPEG" $extpicky -headers "Referer: $_REFERER_URL" -i "$pl" -c copy $erropt -y -threads 0 "$v"; then
                print_warn "Failed to download episode $1"
                return 1
            fi
        fi
    else
        echo "$pl"
    fi
    
    return 0
}

select_episodes_to_download() {
    # Ensure we have the episode list
    download_source
    
    # Show prompt after listing episodes
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
    # Temporarily disable exit on error for batch downloading
    set +e
    
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

    [[ -z "${_ANIME_EPISODE:-}" ]] && _ANIME_EPISODE=$(select_episodes_to_download)
    download_episodes "$_ANIME_EPISODE"
    
    # Re-enable exit on error
    set -e
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
