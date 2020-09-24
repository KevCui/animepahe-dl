# animepahhe-dl

> Bash script to download anime from [animepahe](https://animepahe.com/)

## Table of Contents

- [Dependencies](#dependencies)
- [Installation](#installation)
- [How to use](#how-to-use)
  - [Example](#example)
- [Limitation](#limitation)
- [Disclaimer](#disclaimer)
- [You may like...](#you-may-like)
  - [Don't like animepahe? Want an alternative?](#dont-like-animepahe-want-an-alternative)
  - [What to know when the new episode of your favorite anime will be released?](#what-to-know-when-the-new-episode-of-your-favorite-anime-will-be-released)

## Dependencies

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

## Usage

```
Usage:
  animepahe-dl.sh [-a <anime>] [-e <episode_num1,num2,num3-num4...>] [-l]

Options:
  -a <anime>              Anime name, can be found in anime.list file
  -e <num1,num3-num4...>  Optional, episode number to download
                          multiple episode numbers seperated by ","
                          episode range using "-"
  -l                      Optional, list video link only without downloading
  -h | --help             Display this help message

```

### Usage

Search anime:

```
$ ./animepahe-dl.sh
```

Download first two episodes:

```
$ ./animepahe-dl.sh -a 'one punch man' -e 1,2
```

Stream first twelve episodes using [`mpv`](https://github.com/mpv-player/mpv):

```
$ ./animepahe-dl.sh -l -a 'one punch man' -e 1-12 | mpv --prefetch-playlist --playlist=-
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