const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const vm=require('node:vm');
const handlers={},messages=[],markers=[];
let hostMessage;
const sources={trails:{setData(){}},photos:{setData(){}}};
const map={addControl(){},on(name,...args){handlers[name+':'+(args.length===2?args[0]:'')]=args.at(-1);},getSource(id){return sources[id]},getLayer(){return true},queryRenderedFeatures(){return []},easeTo(){},fitBounds(){}};
class Marker {
 constructor(options){this.options=options;this.events={};markers.push(this)}
 setLngLat(coordinates){this.coordinates=coordinates;return this}
 addTo(){return this} on(name,callback){this.events[name]=callback;return this}
 getLngLat(){return {wrap:()=>({lng:this.coordinates[0],lat:this.coordinates[1]})}}
 remove(){this.removed=true}
}
const page=fs.readFileSync(path.join(__dirname,'../PhotoTrail.Windows/Web/map.html'),'utf8');
const script=page.match(/<script type="module">([\s\S]*?)<\/script>/)[1].replace(/^import .*;$/m,'').replace(/^maplibregl.setWorkerUrl.*;$/m,'');
const context={maplibregl:{Map:function(){return map},NavigationControl:function(){},Marker},document:{getElementById:()=>({textContent:''})},window:{chrome:{webview:{postMessage:data=>messages.push(data),addEventListener:(_,callback)=>hostMessage=callback}}}};
vm.runInNewContext(script,context);
const click=(longitude,latitude)=>handlers['click:']({point:{},lngLat:{wrap:()=>({lng:longitude,lat:latitude})}});
click(135.77,35.01);
assert.equal(markers[0].options.draggable,true);
assert.equal(messages[0].type,'point');
markers[0].coordinates=[-179,20];markers[0].events.dragend();
assert.equal(messages.at(-1).longitude,-179);
assert.equal(messages.at(-1).latitude,20);
const count=messages.length;
for(const point of [[NaN,0],[181,0],[0,91],[Infinity,0]])click(...point);
assert.equal(messages.length,count);
hostMessage({data:{type:'match-preview',point:{Longitude:135,Latitude:35}}});
assert.equal(markers[0].removed,true);
assert.equal(markers[1].options.draggable,true);
markers[1].coordinates=[136,36];markers[1].events.dragend();
assert.equal(messages.at(-1).longitude,136);
assert(messages.every(message=>message.type==='point'));
hostMessage({data:{type:'match-preview',point:null}});
assert.equal(markers[1].removed,true);
handlers['error:']({error:new Error('untrusted request detail')});
assert.equal(messages.at(-1).type,'map-error');
assert.deepEqual(Object.keys(messages.at(-1)),['type']);
console.log('12 map preview/error assertions passed; no real mouse/WebView2 acceptance performed.');
