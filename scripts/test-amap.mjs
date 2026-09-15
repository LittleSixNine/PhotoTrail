import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../GeoTag/Views/Maps/AMap.html', import.meta.url), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
async function setup(preferWebGL = true) {
  const messages = [], addresses = [], conversions = [], handlers = {}, markers = [], searches = [];
  const notice = {};
  const api = {
    Map: class {
      on(name, handler) { handlers[name] = handler; }
      addControl() {}
      add(marker) { markers.push(marker); }
      remove() {}
      setCenter() {}
      setZoomAndCenter() {}
      getZoom() { return this.zoom ?? 10; }
      setZoom(value) { this.zoom = value; }
      setRotation(value) { this.rotation = value; }
      getRotation() { return this.rotation ?? 0; }
    },
    TileLayer: { Satellite: class { show() { this.visible = true; } hide() { this.visible = false; } } },
    PlaceSearch: class { search(query, callback) { searches.push({ query, callback }); } },
    Geocoder: class { getAddress(point, callback) { addresses.push({ point, callback }); } },
    Scale: class {}, ToolBar: class {}, Marker: class { constructor(options) { this.options = options; } },
    convertFrom(point, type, callback) { conversions.push({ point, type, callback }); }
  };
  const window = { webkit: { messageHandlers: { geoTag: { postMessage: value => messages.push(value) } } } };
  const context = vm.createContext({ window, AMap: api, AMapLoader: { load: async () => api },
    setTimeout: (fn, ms) => { const timer = setTimeout(fn, ms); timer.unref(); return timer; }, clearTimeout, document: { querySelectorAll: () => [], getElementById: () => notice, createElement: () => ({}),
      head: { appendChild: script => queueMicrotask(() => script.onload()) } } });
  vm.runInContext(source, context);
  await window.geoTag.start({ key: 'test-only', securityJsCode: 'test-only', preferWebGL });
  return { geo: window.geoTag, messages, addresses, conversions, handlers, markers, searches };
}
const event = { lnglat: { getLat: () => 31.23, getLng: () => 121.48 } };
const address = { regeocode: { addressComponent: { adcode: '310101' } } };
const location = { getLat: () => 31.24, getLng: () => 121.49 };

test('read-only state never requests a location write', async () => {
  const h = await setup();
  await h.handlers.click(event);
  assert.equal(h.addresses.length, 0);
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('new click invalidates older location response immediately', async () => {
  const h = await setup();
  await h.geo.updateSnapshot({ revision: 1, editable: true, point: null });
  const first = h.handlers.click(event), second = h.handlers.click(event);
  assert.equal(h.messages.filter(m => m.type === 'pickStarted').length, 2);
  h.addresses[1].callback('complete', address);
  await second;
  h.addresses[0].callback('complete', address);
  await first;
  const picks = h.messages.filter(m => m.type === 'pick');
  assert.equal(picks.length, 1);
  assert.equal(picks[0].sequence, 2);
});

test('changing selection rejects pending point response', async () => {
  const h = await setup();
  await h.geo.updateSnapshot({ revision: 1, editable: true, point: null });
  const click = h.handlers.click(event);
  await h.geo.updateSnapshot({ revision: 2, editable: true, point: null });
  h.addresses[0].callback('complete', address);
  await click;
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('stale display response cannot replace current marker', async () => {
  const h = await setup();
  const display = h.geo.updateSnapshot({ revision: 1, editable: true,
    point: { latitude: 31.23, longitude: 121.48 } });
  await h.geo.updateSnapshot({ revision: 2, editable: true, point: null });
  h.conversions[0].callback('complete', { locations: [location] });
  await display;
  assert.equal(h.markers.length, 0);
});

test('unchanged position does not trigger another API call', async () => {
  const h = await setup();
  const point = { latitude: 31.23, longitude: 121.48 };
  const display = h.geo.updateSnapshot({ revision: 1, editable: true, point });
  h.conversions[0].callback('complete', { locations: [location] });
  await display;
  await h.geo.updateSnapshot({ revision: 2, editable: false, point });
  assert.equal(h.conversions.length, 1);
  assert.equal(h.conversions[0].type, 'gps');
});


test('markers use self-contained SVG with the tip anchored to the point', async () => {
  const h = await setup();
  await h.geo.preview({ latitude: 31.23, longitude: 121.48 }, false);
  assert.match(h.markers[0].options.content, /<svg/);
  assert.doesNotMatch(h.markers[0].options.content, /<img|<image|href=|src=|url\((?!#)/);
  assert.equal(h.markers[0].options.anchor, 'bottom-center');
  assert.match(h.markers[0].options.content, /M16 42C/);
  assert.match(h.markers[0].options.content, /viewBox="0 0 32 42"/);
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('search returns named candidates without changing photos', async () => {
  const h = await setup();
  const search = h.geo.search('东方明珠');
  h.searches[0].callback('complete', { poiList: { pois: [
    { id: 'test-poi', name: '东方明珠', address: '测试地址', location },
    { id: 'no-coordinate', name: '仅有名称' }
  ] } });
  const results = await search;
  assert.equal(results.length, 1);
  assert.equal(results[0].name, '东方明珠');
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('favorite validation works without photos and remains a distinct intent', async () => {
  const h = await setup();
  const favorite = h.geo.selectSearch({ latitude: 31.23, longitude: 121.48 }, 'favorite', '测试收藏');
  h.addresses[0].callback('complete', address);
  await favorite;
  const pick = h.messages.find(m => m.type === 'pick');
  assert.equal(pick.purpose, 'favorite');
  assert.equal(pick.name, '测试收藏');
});

 test('satellite switching reuses a layer and never changes photo metadata', async () => {
  const h = await setup();
  h.geo.setSatellite(true);
  h.geo.setSatellite(false);
  h.geo.setSatellite(true);
  assert.equal(h.markers.length, 1);
  assert.equal(h.markers[0].visible, true);
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});


test('navigation and region lookup never write photo coordinates', async () => {
  const h = await setup();
  for (const command of ['zoomIn', 'zoomOut', 'north']) h.geo.navigate(command);
  const lookup = h.geo.region({ latitude: 31.23, longitude: 121.48 });
  assert.equal(h.conversions[0].type, 'gps');
  h.conversions[0].callback('complete', { locations: [location] });
  await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(Array.from(h.addresses[0].point), [121.49, 31.24]);
  h.addresses[0].callback('complete', { regeocode: { addressComponent:
    { province: '上海市', city: '上海市', district: '浦东新区' } } });
  assert.equal(await lookup, '上海市 · 浦东新区');
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});


test('WebGL preference is explicit and diagnostics do not expose credentials or coordinates', async () => {
  const preferred = await setup();
  assert.equal(preferred.geo.renderingInfo().preferWebGL, true);
  const baseline = await setup(false);
  assert.equal(baseline.geo.renderingInfo().preferWebGL, false);
  const diagnostic = JSON.stringify(preferred.geo.renderingInfo());
  assert.doesNotMatch(diagnostic, /test-only|latitude|longitude|securityJsCode/);
});
