/* Buildless dashboard; all charts use sanitized, aggregate synthetic reports. */
const $=id=>document.getElementById(id);
const esc=x=>String(x).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const fmt=(x,n=2)=>x===null?'—':Number(x).toFixed(n);
const duration=s=>s<60?`${Math.round(s)} sec`:`${(s/60).toFixed(1)} min`;
let report=null,visible=[];
function options(el,items,selected){el.replaceChildren(...items.map(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=label;return o;}));if(selected!==undefined)el.value=selected;}
const numParameters=r=>Object.keys(r.points[0].parameters).filter(k=>typeof r.points[0].parameters[k]==='number'&&new Set(r.points.map(p=>p.parameters[k])).size>1);
function svg(body,label){return `<svg viewBox="0 0 1000 430" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="${esc(label)}">${body}</svg>`;}
function text(x,y,s,extra=''){return `<text x="${x}" y="${y}" class="axis" ${extra}>${esc(s)}</text>`;}
function showStudy(r){
  if(r.version!==1||r.network_source!=='Synthetic random'||!r.points.length)throw Error('Unsupported report');
  report=r;$('empty').hidden=true;$('experiment').hidden=false;
  const labels={commissions_earned:'Supplier commission income',commissions_paid:'Requester commissions paid',subsidy_spent:'Commission subsidy spent',pending_commissions:'Pending commissions',pending_subsidy:'Pending subsidy commitments',mean_peer_distance:'Mean peer grid distance',external_settled:'External exchanges settled',external_value:'External value exchanged',net_external_cash:'Net external cash (+ into market)',closed_share:'Closed kiosk-tick share',closure_failed_count:'Requests lost: shop closed',closure_failed_value:'Value lost: shop closed',cash_failed_count:'Requests lost: cash shortage',efloat_failed_count:'Requests lost: e-float shortage'};
  const preferred=['service_pct','deposit_service_pct','withdrawal_service_pct','cash_low_share','efloat_low_share','unmet_attempts','trades_settled'];
  const existing=Object.fromEntries([...$('metric').options].map(o=>[o.value,o.textContent]));
  options($('metric'),[...preferred,...Object.keys(labels)].filter(k=>k in r.points[0].metrics).map(k=>[k,labels[k]||existing[k]||k]),'service_pct');
  $('stats').innerHTML=`<article><strong>${r.completed_runs}</strong><span>Completed runs</span></article><article><strong>${r.replicates}</strong><span>Seeds per setting</span></article><article><strong>${r.ticks}</strong><span>Ticks per run</span></article>`;
  const params=r.mode==='oat'?[...new Set(r.points.map(p=>p.varied).filter(v=>v!=='baseline'))]:numParameters(r);
  options($('parameter'),params.map(k=>[k,k]),params.includes('network-density')?'network-density':params[0]);
  options($('grid-y'),params.map(k=>[k,k]),params.includes('settlement-delay')?'settlement-delay':params[1]||params[0]);
  options($('policy'),[...(r.mode==='grid'?[]:[['all','All policies']]),...[...new Set(r.points.map(p=>p.parameters['sharing-mode']))].map(k=>[k,k])],r.mode==='grid'?'Network sharing':'all');
  $('policy-wrap').hidden=true;$('participation-wrap').hidden=r.mode!=='grid';$('grid-y-wrap').hidden=r.mode!=='grid';
  $('oat-view-wrap').hidden=r.mode!=='oat';
  options($('participation'),[...new Set(r.points.map(p=>p.parameters['participation-percent']))].sort((a,b)=>a-b).map(v=>[String(v),`${v}%`]),'100');
  $('caveat').textContent=r.caveat;render();
}
function render(){
  if(!report)return;
  const metric=$('metric').value,param=$('parameter').value;
  visible=report.mode==='grid'?report.points:report.points.filter(p=>$('policy').value==='all'||p.parameters['sharing-mode']===$('policy').value);
  if(report.mode==='oat')visible=visible.filter(p=>p.varied==='baseline'||p.varied===param);
  if(report.mode==='grid'){
    const y=$('grid-y').value;
    const keys=Object.keys(report.points[0].parameters).filter(k=>k!==param&&k!==y&&new Set(report.points.map(p=>JSON.stringify(p.parameters[k]))).size>1);
    const slice=p=>JSON.stringify(keys.map(k=>[k,p.parameters[k]]));
    const slices=[...new Set(report.points.map(slice))],old=$('participation').value;
    const preferred=slices.find(v=>{const p=Object.fromEntries(JSON.parse(v));return (!p['sharing-mode']||p['sharing-mode']==='Network sharing')&&(!p['participation-percent']||p['participation-percent']===100);})||slices[0];
    options($('participation'),slices.map(v=>[v,JSON.parse(v).map(([k,value])=>`${k}: ${value}`).join(' · ')||'All fixed settings']),slices.includes(old)?old:preferred);
    visible=visible.filter(p=>slice(p)===$('participation').value);
  }
  if(report.mode==='oat')oat(metric,param);else if(report.mode==='grid')heatmap(metric);else scatter(metric,param);
  const axes=report.mode==='grid'?[param,$('grid-y').value]:[param];
  const columns=['Setting',...axes,'Mean','SD','Seeds'];
  $('points').innerHTML='<thead><tr>'+columns.map(x=>`<th>${esc(x)}</th>`).join('')+'</tr></thead><tbody>'+visible.map(p=>`<tr><td>${esc(p.id)}</td>${axes.map(axis=>`<td>${esc(p.parameters[axis])}</td>`).join('')}<td>${fmt(p.metrics[metric].mean)}</td><td>${fmt(p.metrics[metric].sd)}</td><td>${p.replicates}</td></tr>`).join('')+'</tbody>';
  $('table-count').textContent=`(${visible.length} settings)`;
  parameterSettings(param);
}
function parameterSettings(param){
  const baseline=report.mode==='oat'?report.points.find(p=>p.varied==='baseline'):null;
  const reference=baseline||report.points[0];
  const keys=Object.keys(reference.parameters);
  $('settings-title').textContent=baseline?'OAT baseline and fixed parameter settings':'Fixed settings and sampled ranges';
  $('settings-note').textContent=baseline?
    'These are the actual study baseline values, not assumed UI defaults. For this curve, only the highlighted parameter changes; every other value stays at baseline.':
    'Fixed values are shared by every setting. Varied parameters show their tested range or levels; joint designs do not have a single executed baseline.';
  $('run-settings').textContent=`${(report.model_version||'v1').toUpperCase()} · ${report.ticks} ticks per run · ${report.replicates} simulation seeds`+
    (report.seeds?` (${report.seeds.join(', ')})`:'')+
    (report.warmup_runs!==undefined?` · ${report.warmup_runs} discarded warm-ups per batch`:'');
  const rows=keys.map(key=>{
    const values=[...new Set(report.points.map(p=>p.parameters[key]))];
    const current=report.mode==='oat'&&key===param;
    const tested=[...new Set((report.mode==='oat'?visible:report.points).map(p=>p.parameters[key]))];
    const levels=values.every(v=>typeof v==='number')?values.slice().sort((a,b)=>a-b):values;
    const role=baseline?(current?'Varied in this curve':'Held at baseline'):(values.length===1?'Fixed':'Varied across settings');
    const value=baseline?reference.parameters[key]:values.length===1?values[0]:levels.length<=5?levels.join(', '):`${levels[0]} – ${levels[levels.length-1]}`;
    const detail=current?'Tested: '+tested.slice().sort((a,b)=>a-b).join(', '):'';
    return `<tr${current?' class="varied-setting"':''}><td>${esc(key)}</td><td>${esc(value)}</td><td>${esc(role)}${detail?'<br><small>'+esc(detail)+'</small>':''}</td></tr>`;
  });
  rows.push('<tr><td>selected-market</td><td>Not used</td><td>Abstract synthetic networks</td></tr>');
  if(report.balance_labels!==undefined)rows.push(`<tr><td>show-balances?</td><td>${esc(report.balance_labels)}</td><td>Display setting</td></tr>`);
  $('settings-table').innerHTML=`<thead><tr><th>Parameter</th><th>${baseline?'Baseline value':'Value / tested range'}</th><th>Role</th></tr></thead><tbody>${rows.join('')}</tbody>`;
}
function oat(metric,param){
  const paired=$('oat-view').value==='paired',baseline=report.points.find(p=>p.varied==='baseline');
  let points=visible.map(p=>({value:Number(p.parameters[param]),mean:p.metrics[metric].mean,
    sd:p.metrics[metric].sd,baseline:p.varied==='baseline'}));
  if(paired){
    points=report.sensitivity.filter(e=>e.parameter===param&&e.metric===metric&&e.paired_difference_mean!==null)
      .map(e=>({value:Number(e.value),mean:e.paired_difference_mean,sd:e.paired_difference_sd,baseline:false}));
    if(baseline)points.push({value:Number(baseline.parameters[param]),mean:0,sd:0,baseline:true});
  }
  points=points.filter(p=>Number.isFinite(p.value)&&Number.isFinite(p.mean)).sort((a,b)=>a.value-b.value);
  if(!points.length){$('chart').textContent='No numeric results for this selection.';return;}
  const xmin=points[0].value,xmax=points[points.length-1].value,xpad=(xmax-xmin)*.07||1;
  let lo=Math.min(0,...points.map(p=>p.mean-(p.sd||0)));
  let hi=Math.max(paired?0:metric.endsWith('_pct')?100:metric.endsWith('_share')?1:0,...points.map(p=>p.mean+(p.sd||0)));
  if(paired){const pad=Math.max((hi-lo)*.15,.01);lo-=pad;hi+=pad;}else if(hi===lo)hi=lo+1;
  const x=v=>95+(v-xmin+xpad)/(xmax-xmin+2*xpad)*825,y=v=>345-(v-lo)/(hi-lo)*280;
  let s='';for(let i=0;i<=5;i++){const v=lo+(hi-lo)*i/5;s+=`<line x1="95" x2="920" y1="${y(v)}" y2="${y(v)}" class="gridline"/>`+text(80,y(v)+4,fmt(v),'text-anchor="end"');}
  for(const value of [...new Set(points.map(p=>p.value))])s+=text(x(value),375,String(Number(value.toFixed(4))),'text-anchor="middle"');
  if(paired)s+=`<line x1="95" x2="920" y1="${y(0)}" y2="${y(0)}" stroke="#52666c"/>`;
  const base=points.find(p=>p.baseline);
  if(base)s+=`<line x1="${x(base.value)}" x2="${x(base.value)}" y1="58" y2="345" stroke="#52666c" stroke-dasharray="4 5"/>`+text(x(base.value),48,'Baseline','text-anchor="middle"');
  s+=`<polyline points="${points.map(p=>`${x(p.value)},${y(p.mean)}`).join(' ')}" fill="none" stroke="#087c79" stroke-width="2"/>`;
  points.forEach(p=>{const xx=x(p.value),sd=p.sd||0,top=y(p.mean+sd),bottom=y(p.mean-sd);
    s+=`<line x1="${xx}" x2="${xx}" y1="${top}" y2="${bottom}" stroke="#172d38"/><line x1="${xx-6}" x2="${xx+6}" y1="${top}" y2="${top}" stroke="#172d38"/><line x1="${xx-6}" x2="${xx+6}" y1="${bottom}" y2="${bottom}" stroke="#172d38"/><circle class="point" cx="${xx}" cy="${y(p.mean)}" r="${p.baseline?7:5}" fill="${p.baseline?'#172d38':'#087c79'}"><title>${esc(`${param}=${p.value}; ${p.baseline?'baseline; ':''}${fmt(p.mean)} ± ${fmt(p.sd)} SD`)}</title></circle>`;});
  s+=text(500,420,param,'text-anchor="middle"')+text(95,20,paired?'Paired change from baseline (percentage points for service rates)':$('metric').selectedOptions[0].textContent);
  $('chart').innerHTML=svg(s,'One-at-a-time numeric response curve');
  $('chart-note').textContent=(paired?'Whiskers show SD of seed-paired differences; baseline change is exactly zero. ':'Points show seed-mean responses; whiskers show between-seed SD. ')+
    'The horizontal axis preserves numerical spacing. Lines connect tested settings, not predictions between them. SD is not a confidence interval.';
}
function scatter(metric,param){
  const xs=visible.map(p=>p.parameters[param]),ys=visible.map(p=>p.metrics[metric].mean),sds=visible.map(p=>p.metrics[metric].sd||0);
  let xmin=Math.min(...xs),xmax=Math.max(...xs),ymin=Math.min(0,...ys.map((y,i)=>y-sds[i])),ymax=Math.max(metric.endsWith('_pct')?100:metric.endsWith('_share')?1:0,...ys.map((y,i)=>y+sds[i]));
  if(xmax===xmin)xmax=xmin+1;if(ymax===ymin)ymax=ymin+1;
  const x=v=>90+(v-xmin)/(xmax-xmin)*830,y=v=>350-(v-ymin)/(ymax-ymin)*300;
  let s='';for(let i=0;i<=5;i++){const yy=ymin+(ymax-ymin)*i/5,xx=xmin+(xmax-xmin)*i/5;s+=`<line x1="90" x2="920" y1="${y(yy)}" y2="${y(yy)}" class="gridline"/>`+text(75,y(yy)+4,fmt(yy),'text-anchor="end"')+text(x(xx),380,fmt(xx),'text-anchor="middle"');}
  visible.forEach(p=>{const m=p.metrics[metric],xx=x(p.parameters[param]),yy=y(m.mean),sd=m.sd||0;s+=`<line x1="${xx}" x2="${xx}" y1="${y(m.mean-sd)}" y2="${y(m.mean+sd)}" stroke="#087c79" opacity=".25"/><circle class="point" cx="${xx}" cy="${yy}" r="5" fill="#087c79" opacity=".8"><title>${esc(p.id+': '+param+'='+fmt(p.parameters[param])+', mean '+fmt(m.mean)+' ± '+fmt(sd)+' SD')}</title></circle>`;});
  s+=text(500,420,param,'text-anchor="middle"');$('chart').innerHTML=svg(s,'Multivariate sample response');
  const correlation=report.sensitivity.find(e=>e.parameter===param&&e.metric===metric);
  $('chart-note').textContent='Each dot is one joint parameter setting, averaged across seeds; whiskers show between-seed SD. '+(correlation?`Marginal Spearman ρ = ${fmt(correlation.spearman_rho)}; this does not isolate a causal effect.`:'');
}
function heatmap(metric){
  const xName=$('parameter').value,yName=$('grid-y').value;
  if(!xName||!yName||xName===yName){$('chart').textContent='Choose two different numerical parameters for the grid axes.';return;}
  const xs=[...new Set(visible.map(p=>p.parameters[xName]))].sort((a,b)=>a-b),ys=[...new Set(visible.map(p=>p.parameters[yName]))].sort((a,b)=>a-b);
  const means=visible.map(p=>p.metrics[metric].mean),min=Math.min(...means),max=Math.max(...means),cellW=760/xs.length,cellH=280/ys.length;
  let s='';visible.forEach(p=>{const i=xs.indexOf(p.parameters[xName]),j=ys.indexOf(p.parameters[yName]),v=p.metrics[metric].mean,t=max===min?.5:(v-min)/(max-min);
    const fill=`hsl(176 46% ${92-t*57}%)`,xx=140+i*cellW,yy=55+j*cellH;
    s+=`<rect x="${xx+2}" y="${yy+2}" width="${cellW-4}" height="${cellH-4}" fill="${fill}"><title>${esc(p.id+': mean '+fmt(v)+' ± '+fmt(p.metrics[metric].sd)+' SD')}</title></rect><text x="${xx+cellW/2}" y="${yy+cellH/2+5}" font-size="20" text-anchor="middle" fill="${t>.65?'white':'#172d38'}">${fmt(v)}</text>`;});
  xs.forEach((v,i)=>s+=text(140+(i+.5)*cellW,365,v,'text-anchor="middle"'));
  ys.forEach((v,i)=>s+=text(120,55+(i+.5)*cellH+4,v,'text-anchor="end"'));
  s+=text(520,410,xName,'text-anchor="middle"')+text(30,195,yName,'transform="rotate(-90 30 195)" text-anchor="middle"');$('chart').innerHTML=svg(s,'Grid parameter response heatmap');
  $('chart-note').textContent='Cells show seed means at the selected axes and other parameter settings. Color scale is local to this selection; higher means darker, not necessarily better.';
}
async function performance(){
  try{const p=await (await fetch('studies/performance.json')).json();if(p.kind!=='performance-benchmark')return;
    const estimates=Object.entries(p.estimates||{}).map(([name,e])=>`<article><b>${esc(name.toUpperCase())}</b><strong>${duration(e.estimated_seconds)}</strong><span>${e.planned_runs} runs · budget ${duration(e.planning_seconds)}</span></article>`).join('');
    $('performance').innerHTML=`<p>${(p.model_version||'v1').toUpperCase()} · ${p.measured_runs} measured runs + ${p.warmup_runs} warm-ups · ${esc(p.environment.os)} · serial runner · benchmark wall time ${duration(p.measured_wall_seconds)}</p><div class="runtime">${estimates}</div><p class="muted">${esc(p.caveat)} The planning allowance uses at least 1.5× measured run costs and is not a confidence bound.</p><details><summary>Inspect measured workloads</summary><div class="table-scroll"><table><thead><tr><th>Workload</th><th>Kiosks</th><th>Density</th><th>Setup (ms)</th><th>Tick (ms)</th></tr></thead><tbody>${p.cases.map(c=>`<tr><td>${esc(c.case)}</td><td>${c['number-of-kiosks']}</td><td>${c['network-density']}</td><td>${fmt(1000*c.setup_seconds)}</td><td>${fmt(1000*c.seconds_per_tick,3)}</td></tr>`).join('')}</tbody></table></div></details>`;
  }catch{/* The page remains usable before any benchmark exists. */}
}
['metric','parameter','grid-y','policy','participation','oat-view'].forEach(id=>$(id).addEventListener('change',render));
$('download').addEventListener('click',()=>{const metric=$('metric').value,param=$('parameter').value;const keys=Object.keys(report.points[0].parameters);const rows=[['setting',...keys,'mean','sd','seeds'],...visible.map(p=>[p.id,...keys.map(k=>p.parameters[k]),p.metrics[metric].mean,p.metrics[metric].sd,p.replicates])];const csv=rows.map(r=>r.map(x=>'"'+String(x??'').replace(/"/g,'""')+'"').join(',')).join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv'}));a.download=`${report.id}-${metric}.csv`;a.click();URL.revokeObjectURL(a.href);});
async function init(){await performance();try{const catalog=await (await fetch('studies/index.json')).json();if(!catalog.studies.length)return;options($('study'),catalog.studies.map(s=>[s.file,s.title]));$('study').addEventListener('change',async()=>{try{showStudy(await (await fetch('studies/'+$('study').value)).json());}catch(e){$('chart').textContent='Could not load this report: '+e.message;}});showStudy(await (await fetch('studies/'+$('study').value)).json());}catch(e){$('empty').querySelector('p').textContent='Serve this folder over HTTP to load study files. '+e.message;}}
init();
