const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const messages=[],scripts=[],callbacks=[],markers=[],layers=[];let receive,clicked;
class Marker{constructor(options){this.options=options;this.events={};markers.push(this)}setMap(map){this.map=map}addListener(name,fn){this.events[name]=fn}}
class Data{constructor(){this.items=[];this.events={};layers.push(this)}setStyle(){}addListener(name,fn){this.events[name]=fn}forEach(fn){[...this.items].forEach(fn)}remove(f){this.items.splice(this.items.indexOf(f),1)}addGeoJson(geojson){this.items=geojson.features}}
const map={addListener(name,fn){if(name==='click')clicked=fn},fitBounds(){},setCenter(){},setZoom(){}};
const context={URLSearchParams,setTimeout:()=>1,clearTimeout(){},document:{getElementById:()=>({textContent:''}),createElement:()=>({}),head:{append:s=>scripts.push(s)}},window:{chrome:{webview:{postMessage:d=>messages.push(d),addEventListener:(_,fn)=>receive=fn}}},google:{maps:{Map:function(){return map},Data,Marker,SymbolPath:{CIRCLE:1},LatLngBounds:class{extend(){}},Geocoder:class{geocode(request,callback){callbacks.push({request,callback})}}}}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../PhotoTrail.Windows/Web/google.js'),'utf8'),context);
assert.equal(messages[0].type,'google-bootstrap');assert.equal(scripts.length,0);
receive({data:{type:'initialize',key:'FAKE_TEST_ONLY_NOT_A_REAL_KEY_12345'}});assert.equal(scripts.length,1);
receive({data:{type:'initialize',key:'FAKE_TEST_ONLY_NOT_A_REAL_KEY_12345'}});assert.equal(scripts.length,1);
context.window.initGoogle();assert.equal(messages.at(-1).type,'ready');
clicked({latLng:{lng:()=>135.77,lat:()=>35.01}});assert.equal(messages.at(-1).type,'point');assert.equal(markers.at(-1).options.draggable,true);
markers.at(-1).events.dragend({latLng:{lng:()=>136,lat:()=>36}});assert.equal(messages.at(-1).longitude,136);
const count=messages.length;clicked({latLng:{lng:()=>181,lat:()=>0}});assert.equal(messages.length,count);
receive({data:{type:'geocode',id:2,point:{Longitude:135.77,Latitude:35.01}}});assert.equal(callbacks.length,1);
const components=[{types:['country'],long_name:'日本',short_name:'JP'},{types:['administrative_area_level_1'],long_name:'京都府'},{types:['locality'],long_name:'京都市'},{types:['sublocality_level_1'],long_name:'左京区'}];
callbacks[0].callback([{address_components:components}],'OK');assert.equal(messages.at(-1).fields.countryCode,'JP');assert.equal(messages.at(-1).fields.city,'京都市');
callbacks[0].callback([{address_components:[...components,{types:['locality'],long_name:'別の市'}]}],'OK');assert.equal(messages.at(-1).fields.city,'');
callbacks[0].callback([],'ZERO_RESULTS');assert.equal(messages.at(-1).status,'ZERO_RESULTS');assert.equal(Object.keys(messages.at(-1).fields).length,0);
context.window.gm_authFailure();assert.equal(messages.at(-1).type,'map-error');assert.equal(Object.keys(messages.at(-1)).length,1);
console.log('17 Google page assertions passed with SDK substitutes; zero network requests.');
