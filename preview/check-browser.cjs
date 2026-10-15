const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  fs.mkdirSync(path.join(__dirname,'../validation'),{recursive:true});
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_EXECUTABLE || '/usr/bin/chromium', headless: true });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 } });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  const snapshot = name => page.screenshot({ path: path.join(__dirname, '../validation', `${name}.png`) });
  try {
    const response = await page.goto('http://localhost:8771/');
    assert.equal(response.status(), 200);
    await page.locator('#loading.hidden').waitFor({ state: 'attached' });
    await page.selectOption('#wallpaper', 'subaru-rewind');
    await page.waitForTimeout(900);
    await page.locator('#reset').click();
    await page.waitForTimeout(1400);
    await snapshot('desktop');
    await page.keyboard.type('wrong-demo');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1100);
    await snapshot('failed-login');
    await page.keyboard.type('test');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(1700);
    await snapshot('success');
    await page.waitForTimeout(2400);
    await page.selectOption('#wallpaper', 'moonlit-forest');
    await page.waitForTimeout(1000);
    assert.equal((await (await page.request.get('http://localhost:8771/api/status')).json()).wallpaper, 'moonlit-forest');
    await snapshot('forest');
    await page.selectOption('#wallpaper', 'subaru-promise');
    await page.waitForTimeout(1000);
    for (const mode of ['gentle', 'still', 'full']) {
      await page.selectOption('#motion', mode);
      await page.waitForFunction(() => !document.querySelector('#motion').disabled);
      const state=await (await page.request.get('http://localhost:8771/api/status')).json();
      assert.equal(state.motion,mode);
      assert.equal(state.wallpaper,'subaru-promise');
      await page.waitForTimeout(500);
    }
    const invalid=await page.request.post('http://localhost:8771/api/motion', {
      headers: {'X-Preview-Action':'1',Origin:'http://localhost:8771'}, data:{motion:'unknown'}
    });
    assert.equal(invalid.status(),400);
    await page.waitForTimeout(1000);
    await snapshot('subaru-promise-final');
    await page.locator('#fullscreen').click();
    assert.equal(await page.evaluate(() => document.fullscreenElement?.tagName), 'HTML');
    await page.waitForTimeout(300);
    await snapshot('fullscreen');
    await page.evaluate(() => document.exitFullscreen());
    await page.setViewportSize({ width: 390, height: 844 });
    await page.waitForTimeout(400);
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await snapshot('mobile');
    await page.setViewportSize({width:1600,height:1000});
    await page.selectOption('#wallpaper','royal-capital');
    await page.waitForTimeout(3200);
    await snapshot('royal-capital');
    const status = await (await page.request.get('http://localhost:8771/api/status')).json();
    assert.ok(Object.values(status.running).every(Boolean));
    assert.deepEqual(errors, []);
    const result = { http: 200, native_stream: true, wallpaper_switch: true, motion_controls: true, invalid_motion_rejected: true, fullscreen: true, mobile_no_overflow: true, errors };
    fs.writeFileSync(path.join(__dirname, '../validation/results.json'), JSON.stringify(result, null, 2));
    console.log(JSON.stringify(result));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exit(1); });
