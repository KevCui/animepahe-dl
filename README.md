# animepahhe-dl

> Bash script to download anime from [animepahe](https://animepahe.com/)

## Table of Contents

- [Dependency](#dependency)
- [Installation](#installation)
- [How to use](#how-to-use)
  - [Example](#example)
- [Limitation](#limitation)
- [Disclaimer](#disclaimer)
- [You may like...](#you-may-like)
  - [Don't like animepahe? Want an alternative?](#dont-like-animepahe-want-an-alternative)
  - [What to know when the new episode of your favorite anime will be released?](#what-to-know-when-the-new-episode-of-your-favorite-anime-will-be-released)

## Dependency

- [jq](https://stedolan.github.io/jq/)
- [pup](https://github.com/EricChiang/pup)
- [fzf](https://github.com/junegunn/fzf)
- [Node.js](https://nodejs.org/en/download/)
- [cf-cookie](https://github.com/KevCui/cf-cookie)

## Installation

- Update submodule and install npm packages, run command:

```bash
$ git clone https://github.com/KevCui/animepahe-dl.git
$ cd animepahe-dl
$ git submodule init
$ git submodule update
$ cd bin
$ npm i puppeteer-core commander
```

## How to use

```
Usage:
  ./animepahe-dl.sh [-a <anime name>] [-s <anime_slug>] [-e <episode_num1,num2,num3-num4...>] [-l]

Options:
  -a <name>               Anime name
  -s <slug>               Anime slug, can be found in $_ANIME_LIST_FILE
                          ingored when "-a" is enabled
  -e <num1,num3-num4...>  Optional, episode number to download
                          multiple episode numbers seperated by ","
                          episode range using "-"
  -l                      Optional, list video link only without downloading
  -h | --help             Display this help message
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

- By default, anime slug is stored in `./anime.list` file. Download "One Punch Man" season 2 episode 3:

```bash
$ ./animepahe-dl.sh -s 82a257c6-d361-69e9-9c43-10b45032a660 -e 3
```

- List "One Punch Man" season 2 all episodes:

```bash
$ ./animepahe-dl.sh -s 82a257c6-d361-69e9-9c43-10b45032a660
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
$ ./animepahe-dl.sh -s 82a257c6-d361-69e9-9c43-10b45032a660 -e 2,2,5,6,7
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
$ ./animepahe-dl.sh -s 82a257c6-d361-69e9-9c43-10b45032a660 -e 2,5-7
[INFO] Downloading Episode 2...
...
[INFO] Downloading Episode 5...
...
[INFO] Downloading Episode 6...
...
[INFO] Downloading Episode 7...
...
```

- Display only video link, used to pipe into `mpv` or other media player:

```bash
$ mpv "$(./animepahe-dl.sh -s 82a257c6-d361-69e9-9c43-10b45032a660 -e 5 -l)"
```

OR the interactive way:

```bash
$ mpv "$(./animepahe-dl.sh -l | grep 'https://')"
```

## Limitation

Recently, animepahe implemented Cloudflare DDoS prevention mechanism with reCAPTCHA challenge. Current method is to fetch necessary cookie value from browser opened by puppeteer. Using this method, user must solve reCAPTCHA correctly at least once per day. The reCAPTCHA page will be prompted in browser.

Sometimes, cookie can be turned invalid by animepahe server for certain reason. In this case, the reCAPTCHA page will be prompted in browser in order to generate a valid cookie.

## Disclaimer

The purpose of this script is to download anime episodes in order to watch them later in case when Internet is not available. Please do NOT copy or distribute downloaded anime episodes to any third party. Watch them and delete them afterwards. Please use this script at your own responsibility.

## You may like...

### Don't like animepahe? Want an alternative?

Check out [twistmoe-dl](https://github.com/KevCui/twistmoe-dl)

### What to know when the new episode of your favorite anime will be released?

Check out this script [tvdb-cli](https://github.com/KevCui/tvdb-cli)

---

<a href="https://www.buymeacoffee.com/kevcui" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-orange.png" alt="Buy Me A Coffee" height="60px" width="217px"></a>