'use strict';
const message=document.getElementById('message');
let map,trails,photos,marker,started=false,loadTimer;
const post=data=>window.chrome.webview.postMessage(data);
function fail(){message.textContent='Google地图不可用，请检查密钥、API权限、计费和网络，或切回默认地图。';post({type:'map-error'});}
window.gm_authFailure=fail;
function preview(point){
 const longitude=point.lng(),latitude=point.lat();
 if(!Number.isFinite(longitude)||!Number.isFinite(latitude)||Math.abs(longitude)>180||Math.abs(latitude)>90)return;
 showPreview({Longitude:longitude,Latitude:latitude});post({type:'point',longitude,latitude});
}
function showPreview(point){
 if(marker){marker.setMap(null);marker=null;}
 if(!point)return;
 // shortcut: legacy Marker avoids a required map ID; migrate if Google schedules removal.
 marker=new google.maps.Marker({map,position:{lng:point.Longitude,lat:point.Latitude},draggable:true});
 marker.addListener('dragend',event=>preview(event.latLng));
}
window.initGoogle=()=>{
 try{
  map=new google.maps.Map(document.getElementById('map'),{center:{lng:135.7681,lat:35.0116},zoom:11});
  trails=new google.maps.Data({map});photos=new google.maps.Data({map});
  trails.setStyle({strokeColor:'#1477d4',strokeWeight:4});
  photos.setStyle(feature=>({icon:{path:google.maps.SymbolPath.CIRCLE,scale:7,fillColor:feature.getProperty('selected')?'#d95914':'#217b43',fillOpacity:1,strokeColor:'white',strokeWeight:2},clickable:true}));
  photos.addListener('click',event=>post({type:'select-photo',id:Number(event.feature.getProperty('id')),revision:Number(event.feature.getProperty('revision'))}));
  map.addListener('click',event=>preview(event.latLng));
  clearTimeout(loadTimer);message.textContent='Google Maps：选点/拖动只作预览，地址查询须显式点击。';post({type:'ready'});
 }catch{fail();}
};
function updateLayer(layer,geojson){layer.forEach(feature=>layer.remove(feature));layer.addGeoJson(geojson);}
function component(components,type,short=false){
 const values=[...new Set(components.filter(c=>Array.isArray(c.types)&&c.types.includes(type)).map(c=>short?c.short_name:c.long_name).filter(v=>typeof v==='string'&&v.length<=256))];
 return values.length===1?values[0]:'';
}
function regions(components){
 return {country:component(components,'country'),countryCode:component(components,'country',true),state:component(components,'administrative_area_level_1'),city:component(components,'locality'),sublocation:component(components,'sublocality_level_1')||component(components,'sublocality')};
}
window.chrome.webview.addEventListener('message',event=>{
 const data=event.data;
 if(data.type==='initialize'&&!started){
  if(typeof data.key!=='string'||!/^[A-Za-z0-9_-]{20,256}$/.test(data.key)){fail();return;}
  started=true;const script=document.createElement('script');
  script.src='https://maps.googleapis.com/maps/api/js?'+new URLSearchParams({key:data.key,v:'quarterly',loading:'async',callback:'initGoogle',auth_referrer_policy:'origin'});
  script.async=true;script.onerror=fail;loadTimer=setTimeout(fail,20000);document.head.append(script);return;
 }
 if(!map)return;
 if(data.type==='tracks'){
  updateLayer(trails,data.geojson);showPreview(null);
  const points=data.geojson.features.flatMap(f=>f.geometry.type==='Point'?[f.geometry.coordinates]:f.geometry.coordinates);
  if(points.length){const bounds=new google.maps.LatLngBounds();for(const p of points)bounds.extend({lng:p[0],lat:p[1]});map.fitBounds(bounds,40);}
 }else if(data.type==='photos'){
  updateLayer(photos,data.geojson);if(data.focus){map.setCenter({lng:data.focus.Longitude,lat:data.focus.Latitude});map.setZoom(14);}
 }else if(data.type==='match-preview')showPreview(data.point);
 else if(data.type==='geocode'&&Number.isSafeInteger(data.id)&&data.id>=0&&data.point){
  const point=data.point;
  if(!Number.isFinite(point.Longitude)||!Number.isFinite(point.Latitude)||Math.abs(point.Longitude)>180||Math.abs(point.Latitude)>90)return;
  try { new google.maps.Geocoder().geocode({location:{lng:point.Longitude,lat:point.Latitude}},(results,status)=>{
   const fields=status==='OK'&&results?.length?regions(results[0].address_components??[]):{};
   post({type:'place',id:data.id,point,status:['OK','ZERO_RESULTS','OVER_QUERY_LIMIT','REQUEST_DENIED','INVALID_REQUEST','UNKNOWN_ERROR','ERROR'].includes(status)?status:'ERROR',fields});
  }); } catch { post({type:'place',id:data.id,point,status:'ERROR',fields:{}}); }
 }
});
post({type:'google-bootstrap'});
