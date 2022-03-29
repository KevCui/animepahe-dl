#!/usr/bin/env node

process.removeAllListeners('warning');
const puppeteer = require('puppeteer-extra');
const StealthPlugin = require('puppeteer-extra-plugin-stealth');
puppeteer.use(StealthPlugin());
const cPath = process.argv[2]; 
const url = process.argv[3]; 
const ua = process.argv[4]; 

(async() => {
  const browser = await puppeteer.launch({executablePath: cPath, headless: true});
  const page = await browser.newPage();
  await page.setUserAgent(ua);
  await page.goto(url, {timeout: 15000, waitUntil: 'domcontentloaded'});
  await page.waitForSelector(".content-wrapper");
  const cookie = await page.cookies();
  console.log(JSON.stringify(cookie));
  await browser.close();
})();
