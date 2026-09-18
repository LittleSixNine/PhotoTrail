import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

const html = readFileSync(new URL('../Sources/PhotoTrail/Views/Maps/AMap.html', import.meta.url), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
async function setup(preferWebGL = true, timeout = 15000, viewport = null, initial = {}) {
  const messages = [], addresses = [], conversions = [], handlers = {}, markers = [], searches = [];
  const notice = {}, mapElement = { clientWidth: viewport?.width ?? 0, clientHeight: viewport?.height ?? 0 };
  const visible = new Set(), fits = [], delays = [], centers = [];
  let mapInstance;
  let now = 0;
  class Clock extends Date { static now() { return now; } }
  const api = {
    Map: class {
      constructor(_, options = {}) { mapInstance = this; this.zoom = options.zoom; this.center = options.center; this.mapStyle = options.mapStyle; }
      on(name, handler) { handlers[name] = handler; }
      addControl() {}
      add(marker) { for (const item of Array.isArray(marker) ? marker : [marker]) { markers.push(item); visible.add(item); } }
      remove(marker) { for (const item of Array.isArray(marker) ? marker : [marker]) visible.delete(item); }
      setFitView(...args) { fits.push(args); }
      setCenter(value) { this.center = value; centers.push(value); }
      setZoomAndCenter(value, center) { this.zoom = value; this.center = center; centers.push(center); }
      lngLatToContainer([longitude, latitude]) {
        return { x: longitude * 10 + (this.panX ?? 0), y: latitude * 10 + (this.panY ?? 0) };
      }
      containerToLngLat(pixel) {
        return { getLng: () => pixel.x / 10, getLat: () => pixel.y / 10 };
      }
      getZoom() { return this.zoom ?? 10; }
      setZoom(value) { this.zoom = value; }
      getCenter() {
        const [longitude, latitude] = this.center ?? [121.48, 31.23];
        return { getLng: () => longitude, getLat: () => latitude };
      }
      setMapStyle(value) { this.mapStyle = value; }
      setRotation(value) { this.rotation = value; }
      getRotation() { return this.rotation ?? 0; }
    },
    TileLayer: { Satellite: class { show() { this.visible = true; } hide() { this.visible = false; } } },
    PlaceSearch: class { search(query, callback) { searches.push({ query, callback }); } },
    Geocoder: class { getAddress(point, callback) { addresses.push({ point, callback }); } },
    Scale: class {}, ToolBar: class {}, Marker: class { constructor(options) { this.options = options; } on() {} },
    Pixel: class { constructor(x, y) { this.x = x; this.y = y; } },
    Polyline: class { constructor(options) { this.options = options; } setOptions(options) { Object.assign(this.options, options); } },
    convertFrom(point, type, callback) { conversions.push({ point, type, callback }); }
  };
  const window = { webkit: { messageHandlers: { photoTrail: { postMessage: value => messages.push(value) } } } };
  const context = vm.createContext({ window, AMap: api, AMapLoader: { load: async () => api },
    Date: Clock, setTimeout: (fn, ms) => {
      if (ms === 5000) { queueMicrotask(fn); return; }
      if (ms !== 15000) { delays.push(ms); now += ms; queueMicrotask(fn); return; }
      const timer = setTimeout(fn, timeout); timer.unref(); return timer; }, clearTimeout, document: { querySelectorAll: () => [], getElementById: id => id === 'map' ? mapElement : notice, createElement: () => ({}),
      head: { appendChild: script => queueMicrotask(() => script.onload()) } } });
  vm.runInContext(source, context);
  await window.photoTrail.start({ key: 'test-only', securityJsCode: 'test-only', preferWebGL, ...initial });
  return { geo: window.photoTrail, messages, addresses, conversions, handlers, markers, searches,
    visible, fits, delays, centers, map: mapInstance };
}
const event = { lnglat: { getLat: () => 31.23, getLng: () => 121.48 } };
const address = { regeocode: { addressComponent: { adcode: '310101' } } };
const location = { getLat: () => 31.24, getLng: () => 121.49 };

test('read-only state never requests a location write', async () => {
  const h = await setup();
  await h.handlers.dblclick(event);
  assert.equal(h.addresses.length, 0);
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('disabled map gestures do not start geocoding', async () => {
  const h = await setup();
  const photos = [{ id: 42, editable: true,
    point: { latitude: 31.23, longitude: 121.48 } }];
  await h.geo.updateSnapshot({ revision: 1, editable: true, point: null, photos,
    allowDoubleClick: false, allowDragPin: false });
  await tick(); completeBatch(h.conversions[0]); await tick();
  await h.handlers.dblclick(event);
  h.geo.pickPhotoAt(42, { x: 1214.8, y: 312.3 });
  assert.equal(h.addresses.length, 0);
  assert.equal(h.messages.filter(m => m.type === 'pickStarted').length, 0);
});

test('new click invalidates older location response immediately', async () => {
  const h = await setup();
  await h.geo.updateSnapshot({ revision: 1, editable: true, point: null });
  const first = h.handlers.dblclick(event), second = h.handlers.dblclick(event);
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
  const click = h.handlers.dblclick(event);
  await h.geo.updateSnapshot({ revision: 2, editable: true, point: null });
  h.addresses[0].callback('complete', address);
  await click;
  assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
});

test('selecting a photo never recenters or reconverts the map', async () => {
  const h = await setup();
  await h.geo.updateSnapshot({ revision: 1, editable: true,
    point: { latitude: 31.23, longitude: 121.48 }, selectedPhotoIDs: [1] });
  await h.geo.updateSnapshot({ revision: 2, editable: true, point: null });
  assert.equal(h.conversions.length, 0);
  assert.equal(h.centers.length, 0);
});

test('startup restores a valid saved view and reports later camera changes', async () => {
  const h = await setup(true, 15000, null,
    { initialCenter: [120.12, 30.21], initialZoom: 14 });
  assert.deepEqual(h.map.center, [120.12, 30.21]);
  assert.equal(h.map.getZoom(), 14);
  h.map.setZoomAndCenter(15, [121.48, 31.23]);
  h.handlers.moveend();
  const camera = h.messages.filter(message => message.type === 'camera').at(-1);
  assert.deepEqual({ ...camera }, { type: 'camera', latitude: 31.23, longitude: 121.48, zoom: 15 });
  assert.equal(h.messages.filter(message => message.type === 'pick').length, 0);
});

test('device startup converts WGS84 once, then only moves the map', async () => {
  const h = await setup();
  const focus = h.geo.focusWGS84({ latitude: 31.23, longitude: 121.48 });
  assert.equal(h.conversions.length, 1);
  h.conversions[0].callback('complete', { locations: [location] });
  assert.equal(await focus, true);
  assert.deepEqual(Array.from(h.map.center), [121.49, 31.24]);
  assert.equal(h.map.getZoom(), 12);
  assert.equal(h.messages.filter(message => message.type === 'pick').length, 0);
  assert.equal(h.markers.length, 0);
});

test('late device location does not override a map view changed meanwhile', async () => {
  const h = await setup();
  const focus = h.geo.focusWGS84({ latitude: 31.23, longitude: 121.48 });
  h.map.setCenter([120, 30]);
  h.conversions[0].callback('complete', { locations: [location] });
  assert.equal(await focus, false);
  assert.deepEqual(h.map.center, [120, 30]);
});

test('cancelled startup does not finish a pending coordinate conversion', async () => {
  const h = await setup();
  const focus = h.geo.focusWGS84({ latitude: 31.23, longitude: 121.48 });
  h.geo.cancelStartup();
  h.conversions[0].callback('complete', { locations: [location] });
  assert.equal(await focus, false);
  assert.deepEqual(Array.from(h.map.center), [121.48, 31.23]);
});

test('explicit photo focus is the only selection-related recenter action', async () => {
  const h = await setup();
  const point = { latitude: 31.23, longitude: 121.48 };
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null,
    photos: [{ id: 7, editable: true, point }] });
  await tick(); completeBatch(h.conversions[0]); await tick();
  assert.equal(h.conversions.length, 1);
  assert.equal(h.centers.length, 0);
  h.geo.focusPhoto(7);
  assert.equal(h.centers.length, 1);
});

test('forwarded wheel zoom works independently of SwiftUI photo overlays', async () => {
  const h = await setup();
  assert.equal(h.map.getZoom(), 12);
  h.geo.zoomByWheel(2, { x: 1000, y: 400 });
  assert.equal(h.map.getZoom(), 12.44);
  assert.notDeepEqual(h.map.center, [121.48, 31.23], 'zoom must preserve the coordinate under the pointer');
  h.geo.zoomByWheel(-100, { x: 1000, y: 400 });
  assert.equal(h.map.getZoom(), 2);
});

test('thirty photo positions stay native and unchanged coordinates reuse conversion', async () => {
  const h = await setup();
  const photos = Array.from({ length: 30 }, (_, id) => ({
    id, editable: true, point: { latitude: 31.23 + id * 0.0001, longitude: 121.48 }
  }));
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null, photos });
  await tick();
  assert.equal(h.conversions.length, 1);
  assert.equal(h.conversions[0].point.length, 30);
  completeBatch(h.conversions[0]);
  await tick();
  const positions = h.messages.filter(message => message.type === 'photoPositions').at(-1).positions;
  assert.equal(positions.flatMap(position => position.ids).length, 30);
  assert.ok(positions.length < 30, 'nearby photos should cross the bridge as clusters');
  assert.doesNotMatch(JSON.stringify(positions), /data:|src=|path|name/);
  await h.geo.updateSnapshot({ revision: 2, editable: false, point: null, photos });
  await tick();
  assert.equal(h.conversions.length, 1);

  const moved = photos.map(photo => ({ ...photo, point: { ...photo.point } }));
  moved[0].point.longitude += 0.01;
  await h.geo.updateSnapshot({ revision: 3, editable: false, point: null, photos: moved });
  await tick();
  assert.equal(h.conversions.length, 2);
  assert.equal(h.conversions[1].point.length, 1, 'moving one photo must not reconvert every photo');
});

test('one thousand photos at one location convert and cross the bridge only once', async () => {
  const h = await setup();
  const photos = Array.from({ length: 1000 }, (_, id) => ({
    id, editable: true, point: { latitude: 31.23, longitude: 121.48 }
  }));
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null, photos });
  await tick();
  assert.equal(h.conversions.length, 1);
  assert.equal(h.conversions[0].point.length, 1, 'duplicate coordinates must be converted once');
  completeBatch(h.conversions[0]);
  await tick();
  const positions = h.messages.filter(message => message.type === 'photoPositions').at(-1).positions;
  assert.equal(positions.length, 1);
  assert.equal(positions[0].ids.length, 1000);
});

test('nearby photo groups stay stable while panning and regroup once movement ends', async () => {
  const h = await setup();
  const photos = [4.8, 5.4].map((longitude, id) => ({
    id, editable: true, point: { latitude: 1, longitude }
  }));
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null, photos });
  await tick(); completeBatch(h.conversions[0]); await tick();
  let positions = h.messages.filter(message => message.type === 'photoPositions').at(-1).positions;
  assert.equal(positions.length, 1);
  h.map.panX = 25;
  h.handlers.mapmove(); await tick();
  positions = h.messages.filter(message => message.type === 'photoPositions').at(-1).positions;
  assert.equal(positions.length, 1, 'panning must not repeatedly split and merge nearby markers');
  h.handlers.moveend();
  positions = h.messages.filter(message => message.type === 'photoPositions').at(-1).positions;
  assert.equal(positions.length, 2, 'groups may update once after movement ends');
});

test('selected offscreen photo emits a clickable edge thumbnail without automatic recentering', async () => {
  const h = await setup(true, 15000, { width: 400, height: 300 });
  const photos = [{ id: 42, editable: true,
    point: { latitude: 31.23, longitude: 121.48 } }];
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null,
    photos, selectedPhotoIDs: [42] });
  await tick(); completeBatch(h.conversions[0]); await tick();
  const message = h.messages.filter(item => item.type === 'photoPositions').at(-1);
  assert.equal(message.edges.length, 1);
  assert.equal(message.edges[0].id, 42);
  assert.equal(h.centers.length, 0);
  h.geo.focusPhoto(42);
  assert.equal(h.centers.length, 1);
});

test('dragging one native photo marker returns only its stable id', async () => {
  const h = await setup();
  const photos = [{ id: 42, editable: true,
    point: { latitude: 31.23, longitude: 121.48 } }];
  await h.geo.updateSnapshot({ revision: 1, editable: false, point: null, photos, selectedPhotoIDs: [42] });
  await tick(); completeBatch(h.conversions[0]); await tick();
  h.geo.pickPhotoAt(42, { x: 1214.8, y: 312.3 });
  h.addresses[0].callback('complete', address);
  await tick();
  const pick = h.messages.find(message => message.type === 'pick');
  assert.equal(pick.purpose, 'photo');
  assert.equal(pick.photoID, 42);
});


test('markers use self-contained SVG with the tip anchored to the point', async () => {
  const h = await setup();
  await h.geo.preview({ latitude: 31.23, longitude: 121.48 }, false);
  assert.match(h.markers[0].options.content, /<svg/);
  assert.doesNotMatch(h.markers[0].options.content, /<img|<image|href=|src=|url\((?!#)/);
  assert.equal(h.markers[0].options.anchor, 'bottom-center');
  assert.match(h.markers[0].options.content, /M9 27H25L17 45Z/);
  assert.match(h.markers[0].options.content, /viewBox="0 0 34 45"/);
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

// Synthetic public locations; no credentials, private photographs or GPX files.
const track = count => Array.from({ length: count }, (_, index) =>
  ({ longitude: 121.48 + index * 0.00001, latitude: 31.23 }));
const tick = () => new Promise(resolve => setImmediate(resolve));
function completeBatch(batch) {
  batch.callback('complete', { locations: batch.point.map(([lng, lat]) =>
    ({ getLng: () => lng + 0.001, getLat: () => lat + 0.001 })) });
}


const display = (id, segments, version = 'v1') => ({ id, segments, version });
async function converted(h, segments, request) {
  const start = h.conversions.length;
  const job = h.geo.convertTracks(segments, request);
  await tick();
  for (let i = start; i < start + segments.reduce((n, segment) => n + Math.ceil(segment.length / 40), 0); i++) {
    completeBatch(h.conversions[i]);
    await tick();
  }
  return await job;
}

test('per-file conversion preserves segments and rendering cached results never resends', async () => {
  const h = await setup(), segments = [track(85), track(2)];
  const original = JSON.stringify(segments);
  const result = await converted(h, segments, 1);
  assert.deepEqual(h.conversions.map(c => c.point.length), [40, 40, 5, 2]);
  assert.equal(h.visible.size, 0);
  h.geo.renderTracks([display('a', result.segments)], 'a');
  assert.equal(h.visible.size, 2);
  assert.deepEqual([...h.visible].map(l => l.options.path.length), [85, 2]);
  assert.equal(h.markers[0].options.strokeColor, '#FF3B30');
  assert.equal(h.markers[0].options.strokeStyle, 'dashed');
  assert.deepEqual(Array.from(h.markers[0].options.strokeDasharray), [10, 5]);
  h.geo.renderTracks([], null);
  assert.equal(h.visible.size, 0);
  h.geo.renderTracks([display('a', result.segments)], 'a');
  h.geo.setTrackStyle('#336699', 5);
  h.geo.fitTracks('a');
  assert.equal(h.conversions.length, 4);
  assert.equal(h.fits[0][0].length, 2);
  assert.equal([...h.visible][0].options.strokeColor, '#336699');
  assert.equal(JSON.stringify(segments), original);
});

test('selection fits only its file and updates opacity without rebuilding lines', async () => {
  const h = await setup();
  const records = [display('a', [track(2)]), display('b', [track(3)])];
  h.geo.renderTracks(records, 'a');
  const first = [...h.visible][0];
  h.geo.renderTracks(records, 'b');
  assert.equal([...h.visible][0], first);
  assert.equal(first.options.strokeOpacity, 0.35);
  h.geo.fitTracks('b');
  assert.equal(h.fits[0][0][0].options.path.length, 3);
  assert.equal(h.conversions.length, 0);
});

test('refresh failure and cancellation retain existing geometry and other files', async () => {
  const h = await setup();
  h.geo.renderTracks([display('a', [track(2)]), display('b', [track(3)])], 'a');
  const lines = [...h.visible];
  const job = h.geo.convertTracks([track(42)], 1);
  await tick();
  completeBatch(h.conversions[0]); await tick();
  h.conversions[1].callback('error', {});
  assert.ok((await job).error);
  assert.deepEqual([...h.visible], lines);
  const cancelled = h.geo.convertTracks([track(80)], 2);
  await tick(); h.geo.cancelTrack(2);
  completeBatch(h.conversions[2]);
  assert.equal((await cancelled).cancelled, true);
  assert.equal(h.conversions.length, 3);
  assert.deepEqual([...h.visible], lines);
});

test('all files share one paced queue and cancelling a queued file does not cancel siblings', async () => {
  const h = await setup();
  const one = h.geo.convertTracks([track(2)], 1);
  const two = h.geo.convertTracks([track(2)], 2);
  const three = h.geo.convertTracks([track(2)], 3);
  h.geo.cancelTrack(2);
  await tick(); assert.equal(h.conversions.length, 1);
  completeBatch(h.conversions[0]); await tick();
  assert.equal(h.conversions.length, 2);
  completeBatch(h.conversions[1]);
  assert.ok((await one).segments);
  assert.equal((await two).cancelled, true);
  assert.ok((await three).segments);
  assert.deepEqual(h.delays, [1100]);
});

test('empty and invalid tracks never request conversion', async () => {
  const h = await setup();
  assert.equal((await h.geo.convertTracks([], 1)).segments.length, 0);
  assert.ok((await h.geo.convertTracks([[{ latitude: 100, longitude: 121 }, ...track(2)]], 2)).error);
  assert.equal(h.conversions.length, 0);
});

test('malformed service responses fail without rendering or producing partial cache data', async () => {
  for (const locations of [[], [location], [location, { getLat: () => NaN, getLng: () => 1 }], [{}, {}]]) {
    const h = await setup();
    const job = h.geo.convertTracks([track(2)], 1); await tick();
    h.conversions[0].callback('complete', { locations });
    const result = await job;
    assert.ok(result.error); assert.equal(result.segments, undefined);
    assert.equal(h.visible.size, 0);
  }
});

test('overseas conversion uses only official returned coordinates', async () => {
  const h = await setup();
  const points = [{ latitude: 37.77, longitude: -122.42 }, { latitude: 37.78, longitude: -122.41 }];
  const job = h.geo.convertTracks([points], 1); await tick();
  h.conversions[0].callback('complete', { locations: points.map(point =>
    ({ getLat: () => point.latitude, getLng: () => point.longitude })) });
  const result = await job;
  assert.equal(result.segments[0][0].longitude, -122.42);
  assert.equal(h.messages.filter(message => message.type === 'pick').length, 0);
});

test('conversion timeout is retryable and late callbacks do not render', async () => {
  const h = await setup(true, 10);
  const job = h.geo.convertTracks([track(2)], 1);
  await new Promise(resolve => setTimeout(resolve, 30));
  assert.equal((await job).error, '服务响应超时');
  completeBatch(h.conversions[0]); await tick();
  assert.equal(h.visible.size, 0);
});

test('long tracks stay sequential and bounded without dropping points', async () => {
  const h = await setup();
  const result = await converted(h, [track(10001)], 1);
  assert.equal(h.conversions.length, 251);
  assert.ok(h.conversions.every(c => c.point.length <= 40));
  assert.equal(result.segments[0].length, 10001);
  assert.equal(h.messages.at(-1).completed, 10001);
});

test('service diagnostics never expose arbitrary response payloads', async () => {
  for (const [result, expected] of [
    [{ info: 'DAILY_QUERY_OVER_LIMIT' }, '高德服务：DAILY_QUERY_OVER_LIMIT'],
    ['INVALID_USER_KEY', '高德服务：INVALID_USER_KEY'],
    [{ info: 'https://example.invalid/?key=secret&locations=1,2' }, '高德坐标转换失败']
  ]) {
    const h = await setup();
    const job = h.geo.convertTracks([track(2)], 1); await tick();
    h.conversions[0].callback('error', result);
    assert.equal((await job).error, expected);
    assert.doesNotMatch(JSON.stringify(h.messages), /secret|locations/);
  }
});

test('531 points are paced and QPS retry preserves the same batch', async () => {
  const h = await setup();
  const job = h.geo.convertTracks([track(531)], 1); await tick();
  h.conversions[0].callback('error', { info: 'CUQPS_HAS_EXCEEDED_THE_LIMIT' }); await tick();
  assert.deepEqual(h.conversions[0].point, h.conversions[1].point);
  for (let index = 1; index <= 14; index++) { completeBatch(h.conversions[index]); await tick(); }
  assert.equal((await job).segments[0].length, 531);
  assert.equal(h.conversions.length, 15);
  assert.equal(h.delays.length, 14);
  assert.ok(h.delays.every(delay => delay >= 1100));
});

test('persistent QPS errors stop after two retries; cancellation suppresses retries', async () => {
  for (const cancel of [false, true]) {
    const h = await setup();
    const job = h.geo.convertTracks([track(2)], 1); await tick();
    for (let i = 0; i < (cancel ? 1 : 3); i++) {
      h.conversions[i].callback('error', { info: 'CUQPS_HAS_EXCEEDED_THE_LIMIT' });
      if (cancel) h.geo.cancelTrack(1);
      await tick();
    }
    const result = await job;
    assert.equal(h.conversions.length, cancel ? 1 : 3);
    assert.ok(cancel ? result.cancelled : result.error);
  }
});


test('all official styles initialize and switch without changing the viewport or photo data', async () => {
  for (const style of ['normal', 'dark', 'light', 'whitesmoke', 'fresh', 'grey',
    'graffiti', 'macaron', 'blue', 'darkblue', 'wine']) {
    const h = await setup(true, 15000, null, { mapStyle: style });
    assert.equal(h.map.mapStyle, `amap://styles/${style}`);
    const center = h.map.center, zoom = h.map.zoom;
    h.geo.setMapStyle('normal');
    h.geo.setMapStyle(style);
    h.geo.setSatellite(true);
    h.geo.setSatellite(false);
    assert.equal(h.map.mapStyle, `amap://styles/${style}`);
    assert.equal(h.map.center, center);
    assert.equal(h.map.zoom, zoom);
    assert.equal(h.conversions.length, 0);
    assert.equal(h.messages.filter(m => m.type === 'pick').length, 0);
  }
  const h = await setup(true, 15000, null, { mapStyle: 'unknown' });
  assert.equal(h.map.mapStyle, 'amap://styles/normal');
  h.geo.setMapStyle('unknown');
  assert.equal(h.map.mapStyle, 'amap://styles/normal');
});
