# animepahe-dl

> Download anime videos from [animepahe](https://animepahe.com/) in terminal

## Table of Contents

- [Dependency](#dependency)
- [How to use](#how-to-use)
  - [Example](#example)
- [Disclaimer](#disclaimer)
- [You may like...](#you-may-like)
  - [Don't like animepahe? Want an alternative?](#dont-like-animepahe-want-an-alternative)
  - [Want to know when the new episode of your favorite anime will be released?](#want-to-know-when-the-new-episode-of-your-favorite-anime-will-be-released)

## Dependency

- [jq](https://stedolan.github.io/jq/)
- [fzf](https://github.com/junegunn/fzf)
- [Node.js](https://nodejs.org/en/download/)
- [selenium-webdriver](https://www.npmjs.com/package/selenium-webdriver): To handle cloudflare ddos protection 
- [ffmpeg](https://ffmpeg.org/download.html)
- [openssl](https://www.openssl.org/source/): optional, needed when using `-t <num>` for faster download

### Example install commands on Ubuntu

```
sudo apt-get install jq fzf ffmpeg nodejs
sudo npm install -g selenium-webdriver
```

openssl is mostly installed by default on most systems and is not recommended to change the system package

## How to use

```
Usage:
  ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-r <resolution>] [-t <num>] [-l] [-d]

Options:
  -a <name>               anime name
  -s <slug>               anime slug/uuid, can be found in $_ANIME_LIST_FILE
                          ignored when "-a" is enabled
  -e <num1,num3-num4...>  optional, episode number to download
                          multiple episode numbers seperated by ","
                          episode range using "-"
                          all episodes using "*"
  -r <resolution>         optional, specify resolution: "1080", "720"...
                          by default, the highest resolution is selected
  -o <language>           optional, specify audio language: "eng", "jpn"...
  -t <num>                optional, specify a positive integer as num of threads
  -l                      optional, show m3u8 playlist link without downloading videos
  -d                      enable debug mode
  -h | --help             display this help message
```

### Example

- Simply run script to search anime name and select the right one in `fzf`:

```bash
$ ./animepahe-dl.sh
<anime list in fzf>
...
```

- Search anime by its name:

```bash
$ ./animepahe-dl.sh -a 'attack on titan'
<anime list in fzf>
```

- By default, anime slug/uuid is stored in `./anime.list` file. Be aware that the value of anime slug/uuid often changes, not permanent. Download "One Punch Man" season 2 episode 3:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e 3
```

- List "One Punch Man" season 2 all episodes:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858
[1] E1 2019-04-09 18:45:38
[2] E2 2019-04-16 17:54:48
[3] E3 2019-04-23 17:51:20
[4] E4 2019-04-30 17:51:37
[5] E5 2019-05-07 17:55:53
[6] E6 2019-05-14 17:52:04
[7] E7 2019-05-21 17:54:21
[8] E8 2019-05-28 22:51:16
[9] E9 2019-06-11 17:48:50
[10] E10 2019-06-18 17:50:25
[11] E11 2019-06-25 17:59:38
[12] E12 2019-07-02 18:01:11
```

- Support batch downloads: list "One Punch Man" season 2 episode 2, 5, 6, 7:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e 2,5,6,7
[INFO] Downloading Episode 2...
...
[INFO] Downloading Episode 5...
...
[INFO] Downloading Episode 6...
...
[INFO] Downloading Episode 7...
...
```

OR using episode range:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e 2,5-7
[INFO] Downloading Episode 2...
...
[INFO] Downloading Episode 5...
...
[INFO] Downloading Episode 6...
...
[INFO] Downloading Episode 7...
...
```

- Download all episodes using `*`:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e '*'
[INFO] Downloading Episode 1...
...
[INFO] Downloading Episode 2...
...
[INFO] Downloading Episode 3...
...
```

- Specify video resolution:

```bash
$ ./animepahe-dl.sh -a jujutsu -e 5 -r 360
[INFO] Select video resolution: 360
[INFO] Downloading Episode 5...
```

- Specify audio language:

```bash
$ ./animepahe-dl.sh -a 'samurai 7' -e 1 -o eng
[INFO] Select audio language: eng
[INFO] Downloading Episode 1...
```

- Enable parallel jobs to download faster:

```bash
$ ./animepahe-dl.sh -a jujutsu -e 1 -t 100
```

:warning: Be aware that the parallel download feature can be sometimes unstable, depending on the server side throttling. But usually, it should be stable with a number of threads below 50.

- Show only m3u8 playlist link, without downloading video file:

```bash
$ ./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e 5 -l
...
```

It's useful to toss m3u8 into media player and stream:

```bash
$ mpv --http-header-fields="Referer: https://kwik.cx/" "$(./animepahe-dl.sh -s 308f5756-6715-e404-998d-92f16b9d9858 -e 5 -l)"
```

## Disclaimer

The purpose of this script is to download anime episodes in order to watch them later in case when Internet is not available. Please do NOT copy or distribute downloaded anime episodes to any third party. Watch them and delete them afterwards. Please use this script at your own responsibility.

## You may like...

### Don't like animepahe? Want an alternative?

Check out [twistmoe-dl](https://github.com/KevCui/twistmoe-dl)

### Want to know when the new episode of your favorite anime will be released?

Check out this script [tvdb-cli](https://github.com/KevCui/tvdb-cli)

---

<a href="https://www.buymeacoffee.com/kevcui" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-orange.png" alt="Buy Me A Coffee" height="60px" width="217px"></a>
