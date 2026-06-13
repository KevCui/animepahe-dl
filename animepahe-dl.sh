#!/usr/bin/env bash
#
# Download anime from animepahe in terminal
#
#/ Usage:
#/   ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-r <resolution>] [-w <workers>] [-l] [-d]
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
#/   -w <workers>            optional, number of concurrent download workers (default: 4)
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

    _HOST="https://animepahe.pw"
    _ANIME_URL="$_HOST/anime"
    _API_URL="$_HOST/api"
    _REFERER_URL="https://kwik.cx/"
    _REFERER_HOST="https://animepahe.pw/"

    _SCRIPT_PATH=$(dirname "$(realpath "$0")")
    _USER_AGENT="$("$_JQ" -r '.ua' "$_SCRIPT_PATH/config.json")"
    _CF_CLEARANCE="$("$_JQ" -r '.cf' "$_SCRIPT_PATH/config.json")"
    _ANIME_LIST_FILE="$_SCRIPT_PATH/anime.list"
    _SOURCE_FILE=".source.json"
}

set_args() {
    expr "$*" : ".*--help" > /dev/null && usage
    _DEFAULT_ANIME_RESOLUTION="1080"
    _ANIME_WORKERS=4
    while getopts ":hlda:s:e:r:o:w:" opt; do
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
            o)
                _ANIME_AUDIO="$OPTARG"
                ;;
            w)
                _ANIME_WORKERS="$OPTARG"
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

    # Validate worker count is a positive integer
    if [[ ! "$_ANIME_WORKERS" =~ ^[0-9]+$ ]] || [[ "$_ANIME_WORKERS" -le 0 ]]; then
        print_error "Number of workers must be a valid positive integer!"
    fi
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
    "$_CURL" -sS -L "$1" -b "cf_clearance=$_CF_CLEARANCE" -A "$_USER_AGENT" --compressed
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
    o="$(get "${_HOST}/play/${_ANIME_SLUG}/${s}")"
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
        print_info "Select video resolution: ${_ANIME_RESOLUTION}p"
        r="$(grep 'data-resolution="'"$_ANIME_RESOLUTION"'"' <<< "${r:-$l}")"
        if [[ -z "${r:-}" ]]; then
            print_warn "Selected video resolution is not available, fallback to default ${_DEFAULT_ANIME_RESOLUTION}p."
        fi
    fi

    if [[ -z "${r:-}" ]]; then
        grep kwik <<< "$l" | grep kwik | grep "$_DEFAULT_ANIME_RESOLUTION" | awk -F '"' '{print $1}'
    else
        awk -F '" ' '{print $1}' <<< "$r"
    fi
}

get_playlist_link() {
    # $1: episode link
    local s l t
    while read -r t; do
        s="$("$_CURL" --compressed -sS -H "Referer: $_REFERER_HOST" "$t" \
            | grep "<script>eval(" \
            | awk -F 'script>' '{print $2}'\
            | sed -E 's/document/process/g' \
            | sed -E 's/querySelector/exit/g' \
            | sed -E 's/eval\(/console.log\(/g')"

        l="$("$_NODE" -e "$s" \
            | grep 'source=' \
            | sed -E "s/.m3u8';.*/.m3u8/" \
            | sed -E "s/.*const source='//")"

        if [[ -n "${l:-}" ]]; then
            echo "$l"
            return
        fi
    done <<< "$1"
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

    local total_eps=${#uniqel[@]}
    if [[ -z "${_LIST_LINK_ONLY:-}" ]]; then
        if [[ -n "${_DEBUG_MODE:-}" ]]; then
            _ANIME_WORKERS=1
        fi
        
        # 1. Resolve playlist links sequentially first to avoid Cloudflare rate-limits
        print_info "Resolving video links sequentially to prevent Cloudflare challenges..."
        local -a resolved_playlists
        local -a active_episodes
        for e in "${uniqel[@]}"; do
            local link
            link=$(get_episode_link "$e")
            if [[ "$link" != *"/"* ]]; then
                print_warn "Wrong download link or episode $e not found!"
                continue
            fi
            
            local playlist
            playlist=$(get_playlist_link "$link")
            if [[ -z "${playlist:-}" ]]; then
                print_warn "Missing video list for episode $e! Skip downloading!"
                continue
            fi
            
            resolved_playlists[$e]="$playlist"
            active_episodes+=("$e")
        done

        local total_active=${#active_episodes[@]}
        if [[ "$total_active" -eq 0 ]]; then
            print_error "No episodes could be resolved for download."
        fi

        if [[ "$_ANIME_WORKERS" -gt "$total_eps" ]]; then
            print_error "Number of workers ($_ANIME_WORKERS) cannot be greater than the number of episodes ($total_eps)!"
        fi

        if [[ "$_ANIME_WORKERS" -eq 1 ]]; then
            for e in "${active_episodes[@]}"; do
                download_episode "$e" "" "${resolved_playlists[$e]}"
            done
        else
            local W="$_ANIME_WORKERS"
            if [[ "$W" -gt "$total_active" ]]; then
                W="$total_active"
            fi
            
            local tmp_dir="$_SCRIPT_PATH/.tmp_progress"
            mkdir -p "$tmp_dir"

            cleanup() {
                local pids
                pids=$(jobs -p)
                if [[ -n "$pids" ]]; then
                    kill $pids 2>/dev/null
                fi
                rm -rf "$tmp_dir" 2>/dev/null
            }
            trap cleanup EXIT INT TERM

            # Print initial space for worker bars
            for i in $(seq 1 "$W"); do
                echo ""
            done

            update_display() {
                local w=$1
                printf "\033[%dA" "$w"
                for i in $(seq 0 $((w-1))); do
                    local file="$tmp_dir/worker_$i"
                    local line=""
                    if [[ -f "$file" ]]; then
                        line=$(cat "$file" 2>/dev/null)
                    fi
                    if [[ -z "$line" ]]; then
                        line="[INFO] Slot $i: Idle"
                    fi
                    printf "\033[K%s\n" "$line"
                done
            }

            local -a worker_pids

            for e in "${active_episodes[@]}"; do
                local slot=-1
                while [[ $slot -eq -1 ]]; do
                    update_display "$W"
                    for i in $(seq 0 $((W-1))); do
                        local pid=${worker_pids[$i]:-}
                        if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
                            slot=$i
                            break
                        fi
                    done
                    if [[ $slot -eq -1 ]]; then
                        sleep 0.1
                    fi
                done

                echo "Initializing Episode $e..." > "$tmp_dir/worker_$slot"
                download_episode "$e" "$slot" "${resolved_playlists[$e]}" &
                worker_pids[$slot]=$!
            done

            local active=true
            while $active; do
                update_display "$W"
                active=false
                for i in $(seq 0 $((W-1))); do
                    local pid=${worker_pids[$i]:-}
                    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                        active=true
                        break
                    fi
                done
                if $active; then
                    sleep 0.1
                fi
            done

            update_display "$W"
            rm -rf "$tmp_dir"
            trap - EXIT INT TERM
        fi
    else
        for e in "${uniqel[@]}"; do
            download_episode "$e" ""
        done
    fi
}

download_episode() {
    # $1: episode number
    # $2: optional worker slot index
    # $3: optional pre-resolved playlist link
    local num="$1" slot="${2:-}" pl="${3:-}" l v erropt='' extpicky=''
    v="$_SCRIPT_PATH/${_ANIME_NAME}/${num}.mp4"

    if [[ -z "$pl" ]]; then
        l=$(get_episode_link "$num")
        if [[ "$l" != *"/"* ]]; then
            print_warn "Wrong download link or episode $1 not found!"
            if [[ -n "$slot" ]]; then
                echo "[ERROR] Episode $num: Link not found!" > "$_SCRIPT_PATH/.tmp_progress/worker_$slot"
            fi
            return
        fi

        pl=$(get_playlist_link "$l")
        if [[ -z "${pl:-}" ]]; then
            print_warn "Missing video list! Skip downloading!"
            if [[ -n "$slot" ]]; then
                echo "[ERROR] Episode $num: Missing video list!" > "$_SCRIPT_PATH/.tmp_progress/worker_$slot"
            fi
            return
        fi
    fi

    if [[ -z ${_LIST_LINK_ONLY:-} ]]; then
        if [[ -n "${_DEBUG_MODE:-}" ]]; then
            print_info "Downloading Episode $1..."
            [[ -z "${_DEBUG_MODE:-}" ]] && erropt="-v error"
            if ffmpeg -h full 2>/dev/null| grep extension_picky >/dev/null; then
                extpicky="-extension_picky 0"
            fi
            "$_FFMPEG" $extpicky -headers "Referer: $_REFERER_URL" -i "$pl" -c copy $erropt -y "$v"
        else
            # Fetch total duration of the stream in seconds
            local total_duration
            total_duration=$("$_CURL" -sS -L -H "Referer: $_REFERER_URL" -A "$_USER_AGENT" "$pl" \
                | grep -E "^#EXTINF:" \
                | cut -d: -f2 \
                | cut -d, -f1 \
                | awk '{sum+=$1} END {printf "%d", sum}')

            if ffmpeg -h full 2>/dev/null| grep extension_picky >/dev/null; then
                extpicky="-extension_picky 0"
            fi

            local outfile=""
            if [[ -n "$slot" ]]; then
                outfile="$_SCRIPT_PATH/.tmp_progress/worker_$slot"
            fi

            "$_FFMPEG" $extpicky -headers "Referer: $_REFERER_URL" -progress - -i "$pl" -c copy -y "$v" 2>/dev/null | awk -v total="$total_duration" -v outfile="$outfile" -v ep="$num" '
                /out_time_us=/ {
                    split($0, a, "=")
                    us = a[2]
                    secs = int(us / 1000000)
                    
                    pct = (total > 0) ? (secs * 100 / total) : 0
                    if (pct > 100) pct = 100
                    
                    bar_width = 30
                    filled = int((pct / 100) * bar_width)
                    empty = bar_width - filled
                    
                    bar = ""
                    for (i=0; i<filled; i++) bar = bar "█"
                    for (i=0; i<empty; i++) bar = bar "░"
                    
                    speed_str = (speed != "") ? " [Speed: " speed "]" : ""
                    
                    if (outfile != "") {
                        if (total > 0) {
                            msg = sprintf("Downloading Episode %d: [%s] %d%% (%ds/%ds)%s", ep, bar, pct, secs, total, speed_str)
                        } else {
                            msg = sprintf("Downloading Episode %d: %ds completed%s", ep, secs, speed_str)
                        }
                        print msg > outfile
                        close(outfile)
                    } else {
                        if (total > 0) {
                            printf "\r\033[32m[INFO]\033[0m Downloading: [%s] %d%% (%ds/%ds)%s", bar, pct, secs, total, speed_str
                        } else {
                            printf "\r\033[32m[INFO]\033[0m Downloading: %ds completed%s", secs, speed_str
                        }
                        fflush()
                    }
                }
                /speed=/ {
                    split($0, a, "=")
                    speed = a[2]
                    gsub(/^[ \t]+|[ \t]+$/, "", speed)
                }
                /progress=end/ {
                    if (outfile != "") {
                        msg = sprintf("[INFO] Episode %d Completed!", ep)
                        print msg > outfile
                        close(outfile)
                    } else {
                        printf "\n"
                    }
                }
            '
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

check_config() {
    if [[ -z "${_CF_CLEARANCE:-}" ]]; then
        print_error "Missing cf_clearance, please add it in config.json!"
    fi
    if [[ -z "${_USER_AGENT:-}" ]]; then
        print_error "Missing user-agent, please add it in config.json!"
    fi
}

main() {
    set_args "$@"
    set_var
    check_config

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
