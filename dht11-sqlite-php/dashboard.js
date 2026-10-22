'use strict';
const $ = id => document.getElementById(id);
const timeFormat = new Intl.DateTimeFormat('en-GB', {timeZone:'Asia/Kuala_Lumpur',day:'2-digit',month:'short',year:'numeric',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false});
const shortTime = new Intl.DateTimeFormat('en-GB', {timeZone:'Asia/Kuala_Lumpur',hour:'2-digit',minute:'2-digit',second:'2-digit',hour12:false});
const dateText = (value, short=false) => (short ? shortTime : timeFormat).format(new Date(value));
const palette = ['#28815f','#357eae','#a96d30','#9867b5','#c35e75','#487d7d'];
function svgElement(tag, attrs={}, text) {
  const element = document.createElementNS('http://www.w3.org/2000/svg',tag);
  Object.entries(attrs).forEach(([key,value])=>element.setAttribute(key,value));
  if(text !== undefined) element.textContent=text;
  return element;
}
function chart(container, rows, field, unit) {
  container.replaceChildren();
  if (!rows.length) { const p=document.createElement('p');p.className='empty';p.textContent='Your graph will appear when readings arrive.';container.append(p);return; }
  const ordered=[...rows].reverse(), values=ordered.map(r=>Number(r[field]));
  let min=Math.min(...values),max=Math.max(...values);
  const padding=Math.max((max-min)*.15,1);min-=padding;max+=padding;
  if(field==='humidity'){min=Math.max(0,min);max=Math.min(100,max);}
  const times=ordered.map(r=>new Date(r.created_at).getTime());
  const earliest=Math.min(...times),latest=Math.max(...times);
  const x=r=>latest===earliest?310:52+(new Date(r.created_at).getTime()-earliest)/(latest-earliest)*516;
  const y=r=>220-(Number(r[field])-min)/(max-min)*185;
  const svg=svgElement('svg',{viewBox:'0 0 600 265',role:'img','aria-label':`${field} in ${unit} for the latest ${rows.length} readings, separated by device`});
  for(let i=0;i<=4;i++) {
    const yy=35+i*185/4;
    svg.append(svgElement('line',{x1:52,y1:yy,x2:568,y2:yy,stroke:'#e9eeea'}));
    svg.append(svgElement('text',{x:44,y:yy+4,'text-anchor':'end',fill:'#7b8c81','font-size':11},(max-i*(max-min)/4).toFixed(1)));
  }
  svg.append(svgElement('text',{x:52,y:248,fill:'#7b8c81','font-size':11},dateText(new Date(earliest),true)));
  svg.append(svgElement('text',{x:568,y:248,'text-anchor':'end',fill:'#7b8c81','font-size':11},dateText(new Date(latest),true)));
  const groups=new Map();
  ordered.forEach(row=>{const key=row.device_id??'Unknown';if(!groups.has(key))groups.set(key,[]);groups.get(key).push(row);});
  const legend=document.createElement('div');legend.className='legend';
  let index=0;
  groups.forEach((group,device)=>{
    const color=groups.size===1?(field==='temperature'?'#28815f':'#357eae'):palette[index++%palette.length];
    svg.append(svgElement('polyline',{points:group.map(r=>`${x(r)},${y(r)}`).join(' '),fill:'none',stroke:color,'stroke-width':2.5,'stroke-linejoin':'round'}));
    group.forEach(row=>{const dot=svgElement('circle',{cx:x(row),cy:y(row),r:3.5,fill:color,tabindex:0});const label=`${device}: ${row[field]} ${unit} · ${dateText(row.created_at)}`;dot.setAttribute('aria-label',label);dot.append(svgElement('title',{},label));svg.append(dot);});
    const label=document.createElement('span');label.style.setProperty('--color',color);label.textContent=device;legend.append(label);
  });
  container.append(svg,legend);
}
function render(data) {
  if(data.error) throw new Error(data.error);
  const rows=data.rows, latest=rows[0];
  $('temperature').textContent=latest?Number(latest.temperature).toFixed(1):'—';
  $('humidity').textContent=latest?Number(latest.humidity).toFixed(1):'—';
  $('temp-device').textContent=$('humidity-device').textContent=latest?(latest.device_id??'Unknown device'):'Waiting for data';
  $('count').textContent=rows.length;
  $('last-time').textContent=latest?dateText(latest.created_at):'—';
  $('record-count').textContent=`${rows.length} records`;
  const body=$('readings');body.replaceChildren();
  rows.forEach(row=>{const tr=document.createElement('tr');[row.id,row.device_id??'Unknown',`${Number(row.temperature).toFixed(1)} °C`,`${Number(row.humidity).toFixed(1)} %`,dateText(row.created_at)].forEach(value=>{const td=document.createElement('td');td.textContent=value;tr.append(td);});body.append(tr);});
  if(!rows.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=5;td.className='empty';td.textContent='No readings yet. Send a reading from your ESP32 to get started.';tr.append(td);body.append(tr);}
  const selected=$('device').value;
  const devices=[...new Set([...data.devices,...(selected?[selected]:[])])];
  $('device').replaceChildren(new Option('All devices',''),...devices.map(id=>new Option(id,id,false,id===selected)));
  chart($('temperature-chart'),rows,'temperature','°C');chart($('humidity-chart'),rows,'humidity','%');
}
let busy=false;
async function refresh(){
  if(busy)return;busy=true;$('refresh').disabled=true;
  try{
    const url=new URL('index.php',window.location.href);url.searchParams.set('format','json');url.searchParams.set('device',$('device').value);
    const response=await fetch(url,{cache:'no-store',signal:AbortSignal.timeout(15000)});
    if(!response.ok)throw new Error('Unable to refresh. Showing the last loaded readings.');
    render(await response.json());$('status').className='';$('status').textContent=`Updated ${shortTime.format(new Date())} · ${$('auto').checked?'refreshes every 10 seconds':'auto-refresh paused'}`;
  }catch(error){$('status').className='error';$('status').textContent=error.message;}finally{busy=false;$('refresh').disabled=false;}
}
try{render(JSON.parse($('initial-data').textContent));}catch(error){$('status').className='error';$('status').textContent=error.message;}
$('refresh').addEventListener('click',refresh);
$('auto').addEventListener('change',()=>{$('status').textContent=$('auto').checked?'Auto-refresh every 10 seconds':'Auto-refresh paused';});
setInterval(()=>{if($('auto').checked&&!document.hidden)refresh();},10000);
