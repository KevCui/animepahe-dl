// ~$ node bypasscf.js <chrome_path> <no_browser_boolean> <url> <user_agent>
//
//   chrome_path:        path to chrome/chromium binary
//   no_browser_boolean: 1 true, headless mode; 0 false, open browser
//   url:                url to visit 
//   user_agent:         browser user agent

const puppeteer = require('puppeteer-core');

(async() => {
    const chrome = process.argv[2];
    const isheadless = Number(process.argv[3]);
    const url = process.argv[4];
    const userAgent = process.argv[5];

    const browser = await puppeteer.launch({executablePath: chrome, headless: isheadless});
    const page = await browser.newPage();
    await page.setUserAgent(userAgent);
    await page.goto(url, {timeout: 30000, waitUntil: 'domcontentloaded'});

    await page.waitFor('.navbar-brand', {timeout: 60000});
    const cookie = await page.cookies();
    console.log(JSON.stringify(cookie));

    await browser.close()
})();
