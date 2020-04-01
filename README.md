animepahhe-dl
=============

animepahhe-dl.sh is a Bash script to download anime from [animepahe](https://animepahe.com/). It supports batch downloads.

## Dependency

- [jq](https://stedolan.github.io/jq/)
- [pup](https://github.com/EricChiang/pup)
- [fzf](https://github.com/junegunn/fzf)
- [Node.js](https://nodejs.org/en/download/)
- [cf-cookie](https://github.com/KevCui/cf-cookie)

## Installation

- Update submodule and install npm packages, run command:

```bash
~$ git submodule update
~$ cd bin
~$ npm i puppeteer-core commander
```

## How to use

```
Usage:
  ./animepahe-dl.sh [-s <anime_slug>] [-e <episode_num1,num2...>]

Options:
  -s <slug>          Anime slug, can be found in $_ANIME_LIST_FILE
  -e <num1,num2...>  Optional, episode number to download
                     multiple episode numbers seperated by ","
  -h | --help        Display this help message
```

### Example

- In case, you don't know anime slug, simply run script. Search and select the right one in fzf:

```
~$ ./animepahe-dl.sh
```

- Download "Attack on Titan" season 3 episode 50:

```
~$ ./animepahe-dl.sh -s attack-on-titan-season-3-part-2 -e 50
```

- List "Attack on Titan" season 3 part 2 all episodes:

```
~$ ./animepahe-dl.sh -s attack-on-titan-season-3-part-2
[50] E50 2019-04-28 19:10:30
[51] E51 2019-05-05 17:56:33
[52] E52 2019-05-12 17:51:06
[53] E53 2019-05-19 18:51:24
[54] E54 2019-05-27 03:03:35
[55] E55 2019-06-03 03:31:57
[56] E56 2019-06-10 01:59:17
...
```

- Support batch downloads: list "Attack on Titan" season 3 episode 50, 51, 52:

```
~$ ./animepahe-dl.sh -s attack-on-titan-season-3-part-2 -e 50,51,52
```

### Don't like animepahe? Want an alternative?

Check out [twistmoe-dl](https://github.com/KevCui/twistmoe-dl)

### What to know when the new episode of your favorite anime will be released?

Check out this script [tvdb-cli](https://github.com/KevCui/tvdb-cli)

## Limitation

Recently, animepahe implemented Cloudflare DDoS prevention mechanism with reCAPTCHA challenge. Current method is to fetch necessary cookie value from browser opened by puppeteer. Using this method, user must solve reCAPTCHA correctly once per day. The reCAPTCHA page will be prompted in browser.

## Disclaimer

The purpose of this script is to download anime episodes in order to watch them later in case when Internet is not available. Please do NOT copy or distribute downloaded anime episodes to any third party. Watch them and delete them afterwards. Please use this script at your own responsibility.
