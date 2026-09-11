"""Standalone, offline comparison view; no map tiles, CDN, or telemetry."""
from dataclasses import replace
import json
from pathlib import Path

from track_analysis import analyze


def write_preview(points, policy, path):
    if len(points) > 20000:
        raise ValueError("交互预览最多 20000 点；请按行程分割，或使用 analyze 输出完整报告。")
    thresholds = sorted({v for v in (5, 10, 15, 30, 60, policy.infer_after) if v <= policy.max_infer_gap})
    payload = {"selected": str(float(policy.infer_after)),
               "reports": {str(float(v)): analyze(points, replace(policy, infer_after=v)) for v in thresholds}}
    encoded = json.dumps(payload, ensure_ascii=False, allow_nan=False).replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
    html = TEMPLATE.replace("__DATA__", encoded)
    with Path(path).open("x", encoding="utf-8") as handle:
        handle.write(html)


TEMPLATE = r'''<!doctype html>
<html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PhotoTrail · GPS 轨迹预览</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f5f3ee;color:#243436;font:15px/1.65 system-ui,-apple-system,sans-serif}header{padding:28px 36px 18px;border-bottom:1px solid #d7dad4}h1{font-size:27px;margin:3px 0;font-weight:650}small,.muted{color:#667673}main{display:grid;grid-template-columns:minmax(0,1fr) 330px;min-height:600px}section{padding:24px 36px}aside{padding:24px;background:#eceee8;border-left:1px solid #d7dad4}label{display:block;margin-top:18px;font-weight:600}select,input{max-width:100%}select{font:inherit;padding:5px 8px;background:white;border:1px solid #afb9af;border-radius:5px}input[type=range]{width:100%;accent-color:#ba5033}svg{width:100%;height:460px;background:#fafaf6;border:1px solid #d7dad4}#details{white-space:pre-line}#result{padding:13px;background:#fffaf1;border-left:3px solid #b6573c;font-variant-numeric:tabular-nums;white-space:pre-line}table{border-collapse:collapse;width:100%;font-size:13px}td,th{text-align:left;border-bottom:1px solid #d3d7ce;padding:6px}button{font:inherit;border:1px solid #adb8b0;background:transparent;padding:5px 12px;border-radius:5px;cursor:pointer}.legend{margin:10px 0;font-size:13px}.legend span{margin-right:16px}.dense{color:#39796a}.infer{color:#b65332}.gap{color:#95636f}.hit{cursor:pointer}footer{padding:15px 36px;border-top:1px solid #d7dad4;font-size:12px;color:#64706a}@media(max-width:850px){main{grid-template-columns:1fr}aside{border:0}section{padding:20px}svg{height:360px}}
</style>
<header><small>PHOTOTRAIL · 本地只读预览</small><h1>何时需要推理轨迹？</h1><div class="muted">改变阈值，比较同一份轨迹。曲线代表候选估算；没有在线地图底图，也没有上传数据。</div></header>
<main><section><svg id="plot" viewBox="0 0 900 520" role="img" aria-label="轨迹与位置估算图"></svg>
<div class="legend"><span class="dense">● 原始连线</span><span class="infer">● 曲线／线性候选</span><span class="gap">┄ 待检查／断点（不生成位置）</span></div>
<label for="clock">拍摄时间</label><input id="clock" type="range" min="0" max="1000" step="1"><div id="clockText"></div><p id="result" aria-live="polite"></p>
<label for="segment">检查区间</label><select id="segment"></select><button id="midpoint">查看区间中点时间</button><p id="details"></p>
</section><aside><label for="threshold">超过多少秒才尝试推理</label><select id="threshold"></select><p class="muted">等于阈值时仍保留原始连线。密集区间若位移异常，会进入待检查；不会强行平滑。</p>
<p id="summary"></p><table><thead><tr><th>阈值</th><th>候选区间</th><th>待检查／断点</th></tr></thead><tbody id="comparison"></tbody></table>
<p id="policy" class="muted"></p><p class="muted">这些阈值是可调整的初始策略。改变阈值不等于提高定位准确率；需要真实行程对照。</p></aside></main>
<footer>离线米制投影示意图 · 记录点保持原样 · 不从轨迹覆盖范围外推位置 · 本页面可能包含你的位置信息，请按私人数据保管。</footer>
<script type="application/json" id="data">__DATA__</script><script>
const data=JSON.parse(document.getElementById('data').textContent), $=id=>document.getElementById(id);
const labels={dense:'密集记录',infer:'推理候选',stationary:'推测停留',review:'待检查',gap:'断点',jump:'异常位移'};
let report, marker, sx, sy, currentTime;
const fmt=t=>new Date(t*1000).toLocaleString('zh-CN',{hour12:false})+'（浏览器当地时区）';
for(const key of Object.keys(data.reports)){
 const option=document.createElement('option');option.value=key;option.textContent=Number(key)+' 秒';$('threshold').append(option);
 const r=data.reports[key], d=r.summary.decisions, tr=document.createElement('tr');
 for(const v of [Number(key)+' 秒',d.infer||0,(d.review||0)+(d.gap||0)+(d.jump||0)]){const td=document.createElement('td');td.textContent=v;tr.append(td)}$('comparison').append(tr);
}
$('threshold').value=data.selected;
function node(tag,attrs){const n=document.createElementNS('http://www.w3.org/2000/svg',tag);for(const[k,v]of Object.entries(attrs))n.setAttribute(k,v);return n}
function update(){
 report=data.reports[$('threshold').value];const anchors=report.anchors,o=anchors[0];
 const project=(lat,lon)=>[6371008.8*((lon-o.longitude+540)%360-180)*Math.PI/180*Math.cos(o.latitude*Math.PI/180),6371008.8*(lat-o.latitude)*Math.PI/180];
 const positions=anchors.map(p=>project(p.latitude,p.longitude));
 let minX=Infinity,maxX=-Infinity,minY=Infinity,maxY=-Infinity;for(const[x,y]of positions){minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y)}
 const scale=Math.min(780/Math.max(maxX-minX,10),400/Math.max(maxY-minY,10));
 sx=(lat,lon)=>450+(project(lat,lon)[0]-(minX+maxX)/2)*scale;sy=(lat,lon)=>260-(project(lat,lon)[1]-(minY+maxY)/2)*scale;
 const svg=$('plot');svg.replaceChildren();
 for(let x=50;x<=850;x+=100)svg.append(node('line',{x1:x,y1:40,x2:x,y2:480,stroke:'#e3e6de'}));
 for(let y=60;y<=460;y+=100)svg.append(node('line',{x1:30,y1:y,x2:870,y2:y,stroke:'#e3e6de'}));
 const scaleText=node('text',{x:35,y:505,fill:'#64706a','font-size':13});scaleText.textContent='网格横向约 '+Math.round(100/scale)+' 米 · 北 ↑';svg.append(scaleText);
 $('segment').replaceChildren();
 for(const r of report.intervals){
  const a=anchors[r.index],b=anchors[r.index+1],orig=[[a.timestamp,a.latitude,a.longitude],[b.timestamp,b.latitude,b.longitude]];
  const pts=r.samples.length?r.samples:orig;
  const color=r.decision==='infer'?'#b65332':r.decision==='dense'?'#39796a':r.decision==='stationary'?'#537ea0':'#95636f';
  if(r.method==='curve')svg.append(node('polyline',{points:orig.map(p=>sx(p[1],p[2])+','+sy(p[1],p[2])).join(' '),fill:'none',stroke:'#a9b3a8','stroke-width':1}));
  const line=node('polyline',{points:pts.map(p=>sx(p[1],p[2])+','+sy(p[1],p[2])).join(' '),fill:'none',stroke:color,'stroke-width':3,'stroke-dasharray':r.samples.length?'':'4 6'});svg.append(line);
  const hit=line.cloneNode();hit.setAttribute('stroke','transparent');hit.setAttribute('stroke-width','16');hit.setAttribute('class','hit');hit.addEventListener('click',()=>{$('segment').value=r.index;details()});svg.append(hit);
  const option=document.createElement('option');option.value=r.index;option.textContent='#'+(r.index+1)+' · '+r.seconds+' 秒 · '+labels[r.decision];$('segment').append(option);
 }
 for(const p of anchors)svg.append(node('circle',{cx:sx(p.latitude,p.longitude),cy:sy(p.latitude,p.longitude),r:3.5,fill:'#243436'}));
 marker=node('circle',{r:7,fill:'#f2ba3d',stroke:'#263c39','stroke-width':2});svg.append(marker);
 const d=report.summary.decisions;$('summary').textContent=anchors.length+' 个记录点，'+(d.dense||0)+' 段密集记录，'+(d.infer||0)+' 段推理候选。';
 $('policy').textContent='自动候选上限 '+report.policy.max_infer_gap+' 秒；断点上限 '+report.policy.break_after+' 秒；密集位移上限 '+report.policy.dense_distance+' 米。';
 $('clock').min=anchors[0].timestamp;$('clock').max=anchors[anchors.length-1].timestamp;$('clock').step='.1';
 $('clock').value=currentTime??anchors[0].timestamp;details();move();
}
function details(){const r=report.intervals[Number($('segment').value)];$('details').textContent=r?'间隔 '+r.seconds+' 秒 · 位移 '+r.meters+' 米\n'+r.reason:'只有一个记录点，没有可插值的区间。'}
function move(){
 const t=Number($('clock').value);currentTime=t;$('clockText').textContent=fmt(t);
 const anchor=report.anchors.find(p=>Math.abs(p.timestamp-t)<.00001);let lat,lon,description;
 if(anchor){lat=anchor.latitude;lon=anchor.longitude;description='原始观测点';const i=report.anchors.indexOf(anchor);if([i-1,i].some(j=>report.intervals[j]?.decision==='jump'))description+=' · 邻近有异常位移，需检查'}else{
 const r=report.intervals.find(r=>{const a=report.anchors[r.index],b=report.anchors[r.index+1];return a.timestamp<t&&t<b.timestamp});
 if(r&&r.samples.length){let k=1;while(k<r.samples.length-1&&r.samples[k][0]<t)k++;const a=r.samples[k-1],b=r.samples[k],u=(t-a[0])/(b[0]-a[0]);lat=a[1]+(b[1]-a[1])*u;lon=((a[2]+((b[2]-a[2]+540)%360-180)*u+540)%360)-180;description=labels[r.decision]+(r.decision==='infer'?' · 需人工检查':'');}
 else description=r?r.reason:'不在轨迹覆盖区间内';
 }
 marker.style.display=lat===undefined?'none':'';
 if(lat!==undefined){marker.setAttribute('cx',sx(lat,lon));marker.setAttribute('cy',sy(lat,lon));$('result').textContent=description+'\n纬度 '+lat.toFixed(7)+' · 经度 '+lon.toFixed(7)}else $('result').textContent='未生成位置\n'+description;
}
$('threshold').addEventListener('change',update);$('clock').addEventListener('input',move);$('segment').addEventListener('change',details);
$('midpoint').addEventListener('click',()=>{const r=report.intervals[Number($('segment').value)];if(r){$('clock').value=(report.anchors[r.index].timestamp+report.anchors[r.index+1].timestamp)/2;move()}});update();
</script></html>'''
