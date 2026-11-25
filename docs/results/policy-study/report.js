/* Tables use graph-level synthetic aggregates. The static report works without JavaScript. */
const familyNames={pooled:'Pooled primary',corrected_hub:'Corrected hub sensitivity'};
const policyOrder=['isolated','external','network-s0','network-s50','network-s100','fallback-s0','fallback-s50','fallback-s100'];
const contrastOrder=['external_vs_isolated','network_vs_isolated','fallback_vs_isolated','add_external','add_network','network_half','network_full','network_full_vs_half','fallback_half','fallback_full','fallback_full_vs_half'];
const number=(value,digits=2)=>value==null?'—':Number(value).toFixed(digits);
const change=value=>(value>0?'+':'')+number(value)+' pp';
function rows(tableId,records){
  const body=document.createElement('tbody');
  for(const values of records){
    const row=document.createElement('tr');
    values.forEach((value,index)=>{const cell=document.createElement('td');cell.textContent=value;if(index>0&&String(value).startsWith('-'))cell.className='loss';row.append(cell);});
    body.append(row);
  }
  document.querySelector('#'+tableId+' tbody').replaceWith(body);
}
function render(report){
  const family=document.getElementById('family').value;
  const final=report.overall.filter(r=>r.generator===family&&r.mode==='cumulative'&&r.tick===1000);
  const byPolicy=Object.fromEntries(final.map(r=>[r.policy,r]));
  document.getElementById('policy-caption').textContent=`${familyNames[family]} · 460 graphs · 20 seeds per graph · 1,000 ticks. Charts display both families; tables follow this selection.`;
  rows('policy-table',policyOrder.map(id=>{const r=byPolicy[id];return [report.policies[id],number(r.service_pct)+'%',change(r.gain_pp),number(r.harm_pct,1)+'%',number(r.closed_pct,1)+'%',number(r.subsidy_per_kiosk,0)];}));
  const contrasts=Object.fromEntries(report.contrasts.filter(r=>r.generator===family).map(r=>[r.contrast,r]));
  rows('contrast-table',contrastOrder.map(id=>{const r=contrasts[id];return [report.contrast_labels[id],change(r.gain_pp),`${number(r.gain_pp_q10)} to ${number(r.gain_pp_q90)} pp`,number(r.harm_pct,1)+'%',number(r.large_harm_pct,1)+'%'];}));
  rows('failure-table',['isolated','external','network-s0','fallback-s0'].map(id=>{const r=byPolicy[id];return [report.policies[id],...['request_service_pct','closure_failure_pct','cash_failure_pct','efloat_failure_pct'].map(key=>number(r[key])+'%')];}));
}
document.getElementById('size-response').addEventListener('change',event=>{
  const image=document.getElementById('size-figure');
  image.src='figures/size-'+event.target.value+'.svg';
  image.alt=event.target.selectedOptions[0].textContent+' served by size under four unsubsidized policies and both generators.';
});
document.getElementById('time-view').addEventListener('change',event=>{
  const image=document.getElementById('time-figure');
  image.src='figures/time-'+event.target.value+'.svg';
  image.alt=event.target.value==='interval'?'Service within four successive time windows.':'Cumulative service through four checkpoints.';
});
fetch('analysis.json').then(response=>{if(!response.ok)throw Error('Aggregate data unavailable');return response.json();}).then(report=>{
  if(report.kind!=='completed-synthetic-policy-study'||report.checks.runs!==147200||report.checks.snapshots!==588800)throw Error('Unexpected aggregate report');
  document.getElementById('family').addEventListener('change',()=>render(report));
  render(report);
  document.getElementById('data-status').textContent='Aggregate tables loaded. All 147,200 runs and 588,800 snapshots passed validation. Network variation is descriptive, not a population confidence interval.';
}).catch(()=>{document.getElementById('data-status').textContent='Interactive tables could not load. Pooled summaries and figures remain available; serve the page over HTTP to enable generator selection.';document.getElementById('family').disabled=true;});
