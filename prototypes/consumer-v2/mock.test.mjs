import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import vm from 'node:vm';
const directory = path.dirname(fileURLToPath(import.meta.url));
const read = name => readFileSync(path.join(directory, name), 'utf8');
const modelCode = read('model.js');
const appCode = read('app.js');
function demo() {
  const nodes = new Map(), listeners = {};
  const node = id => {
    if (!nodes.has(id)) nodes.set(id, {
      innerHTML: '', textContent: '', hidden: false, open: false,
      classList: { toggle() {} }, focus() {}, isConnected: true,
      showModal() { this.open = true; }, close() { this.open = false; },
    });
    return nodes.get(id);
  };
  const context = { window: {}, document: {
    getElementById: node, querySelector: () => ({focus(){}}), activeElement:null,
    addEventListener: (name,fn) => { listeners[name] = fn; },
  }, setTimeout(){}, clearTimeout(){} };
  vm.runInNewContext(modelCode, context);
  vm.runInNewContext(appCode, context);
  return { api:context.window.fardaDemo, context, listeners, screen:()=>node('screen').innerHTML, sheet:()=>node('sheet-content').innerHTML };
}
function enableCalls(d) { assert.equal(d.api.submit('call-consent',{verified:true,consent:true}),true); }
test('all nine views render in every hardware scenario',()=>{
  const d=demo();
  for(const scenario of ['connected','waiting','offline','uncertain','low']) {
    d.api.send('scenario',scenario);
    for(const view of ['today','calendar','refills','you','routine','vial','calls','live','circle']) {
      d.api.go(view);assert.ok(d.screen().length>400);assert.doesNotMatch(d.screen(),/undefined|NaN/);
    }
  }
});
test('dose logging requires an explicit second action and preserves a correction trail',()=>{
  const d=demo();d.api.act('log');assert.equal(d.api.state().dose,'pending');
  assert.match(d.sheet(),/Only confirm if you already took it/);
  d.api.act('log-save');assert.equal(d.api.state().dose,'taken');
  d.api.act('undo');assert.equal(d.api.state().dose,'pending');
  assert.equal(d.api.state().audit.length,2);
});
test('offline and uncertain readings never become taken or missed',()=>{
  const d=demo();
  for(const scenario of ['offline','uncertain']) {
    d.api.send('scenario',scenario);d.api.act('sync');
    assert.equal(d.api.state().dose,'pending');assert.equal(d.api.state().scenario,scenario);
  }
});
test('hardware-free logging remains available',()=>{
  const d=demo();d.api.send('scenario','waiting');d.api.act('log-save');
  assert.equal(d.api.state().dose,'taken');assert.equal(d.api.state().scenario,'waiting');
});
test('calendar validates dates and traverses year boundaries',()=>{
  const d=demo();assert.equal(d.api.send('date','2026-02-30'),false);
  d.api.send('date','2026-12-31');d.api.send('month',1);
  assert.equal(d.api.state().year,2027);assert.equal(d.api.state().month,0);
  d.api.send('month',-1);assert.equal(d.api.state().year,2026);assert.equal(d.api.state().month,11);
});
test('calendar distinguishes a missing record, a self-report and a refill reminder',()=>{
  const d=demo();d.api.go('calendar');
  d.api.send('date','2026-10-13');assert.match(d.screen(),/No confirmation saved/);
  assert.doesNotMatch(d.screen(),/missed dose/i);
  d.api.send('date','2026-10-12');assert.match(d.screen(),/Self-reported at 9:04/);
  d.api.send('date','2026-10-16');d.api.send('filter','refills');
  assert.match(d.screen(),/not a promised pickup date/);assert.doesNotMatch(d.screen(),/<h3>Planned reminder/);
});
test('keyboard calendar navigation moves a week and crosses months',()=>{
  const d=demo();d.api.go('calendar');d.api.send('date','2026-10-30');
  let prevented=false;
  d.listeners.keydown({key:'ArrowDown',target:{dataset:{date:'2026-10-30'}},preventDefault(){prevented=true;}});
  assert.equal(prevented,true);assert.equal(d.api.state().selectedDate,'2026-11-06');
});
test('routine edits escape input, validate time, and do not rewrite existing occurrence time',()=>{
  const d=demo();assert.equal(d.api.submit('routine',{name:'Routine <img>',time:'07:30'}),true);
  d.api.go('routine');assert.match(d.screen(),/Routine &lt;img&gt;/);
  assert.equal(d.api.state().occurrence.time,'09:00');
  assert.equal(d.api.submit('routine',{name:'Routine',time:'28:90'}),false);
  d.api.go('calendar');d.api.send('date','2026-10-15');assert.match(d.screen(),/7:30 AM/);
  d.api.send('date','2026-10-14');assert.match(d.screen(),/9:00 AM/);
});
test('unreadable label cannot be activated by inference or without review',()=>{
  const d=demo();
  assert.equal(d.api.submit('label',{name:'Test',directions:'',confirmed:true}),false);
  assert.equal(d.api.submit('label',{name:'Test',directions:'Verified wording',confirmed:false}),false);
  assert.equal(d.api.submit('label',{name:'Test',directions:'Verified wording',confirmed:true}),true);
  assert.equal(d.api.state().labelReviewed,true);assert.equal(d.api.state().medication.name,'Daily medication');
});
test('pharmacy handoff is not a submitted or accepted order and does not change stock',()=>{
  const d=demo();d.api.act('refill-handoff');
  assert.equal(d.api.state().refill.stage,'handoff');assert.equal(d.api.state().medication.count,6);
  assert.equal(d.api.state().audit[0].detail,'No request sent by Farda');
});
test('refill receipt and explicit count are required; duplicate receipt cannot inflate stock',()=>{
  const d=demo();
  assert.equal(d.api.submit('refill-add',{quantity:'30',confirmed:true}),false);
  d.api.act('refill-handoff');d.api.act('refill-requested');d.api.act('refill-ready');d.api.act('refill-collected');
  assert.equal(d.api.state().medication.count,6);
  assert.equal(d.api.submit('refill-add',{quantity:'30',confirmed:false}),false);
  assert.equal(d.api.submit('refill-add',{quantity:'30',confirmed:true}),true);
  assert.equal(d.api.state().medication.count,36);
  assert.equal(d.api.submit('refill-add',{quantity:'30',confirmed:true}),false);
  assert.equal(d.api.state().medication.count,36);
});
test('count zero is valid; empty, negative and fractional inputs are rejected',()=>{
  const d=demo();
  for(const count of ['','-1','2.2','1000']) assert.equal(d.api.submit('stock',{count}),false);
  assert.equal(d.api.submit('stock',{count:'0'}),true);assert.equal(d.api.state().medication.count,0);
});
test('calls require separate consent and verification; OTP alone is not opt-in',()=>{
  const d=demo();assert.equal(d.api.send('call-enable'),false);assert.equal(d.api.send('call-start'),false);
  assert.equal(d.api.submit('call-consent',{verified:true,consent:false}),false);
  d.api.send('call-verify');assert.equal(d.api.send('call-enable'),false);
  enableCalls(d);assert.equal(d.api.state().calls.enabled,true);
});
test('answered call is not a dose confirmation and PIN must precede logging',()=>{
  const d=demo();enableCalls(d);d.api.act('call-start');d.api.act('call-answer');
  assert.equal(d.api.state().dose,'pending');assert.equal(d.api.send('log','phone'),false);
  assert.equal(d.api.state().calls.stage,'greeting');d.api.act('call-private');
  assert.equal(d.api.submit('call-pin',{pin:'9999'}),false);
  assert.equal(d.api.submit('call-pin',{pin:'2468'}),true);
  assert.equal(d.api.send('log','phone'),false);
  d.api.act('call-choose-log');assert.equal(d.api.state().dose,'pending');
  d.api.act('call-log');assert.equal(d.api.state().dose,'taken');assert.equal(d.api.state().source,'Phone self-report');
});
test('no answer keeps the dose unconfirmed and does not permit repeated calls',()=>{
  const d=demo();enableCalls(d);d.api.act('call-start');d.api.act('call-no-answer');
  assert.equal(d.api.state().dose,'pending');assert.equal(d.api.state().calls.stage,'no-answer');
  assert.equal(d.api.send('call-start'),false);assert.equal(d.api.state().calls.attempts,1);
});
test('saving a dose cancels the outstanding call; undo does not create a second attempt',()=>{
  const d=demo();enableCalls(d);d.api.act('call-start');d.api.act('log-save');
  assert.equal(d.api.state().calls.stage,'cancelled');
  d.api.act('undo');assert.equal(d.api.send('call-start'),false);
});
test('opt out cancels the call and revokes consent',()=>{
  const d=demo();enableCalls(d);d.api.act('call-start');d.api.act('call-disable');
  assert.equal(d.api.state().calls.enabled,false);assert.equal(d.api.state().calls.consent,false);
  assert.equal(d.api.state().calls.stage,'cancelled');assert.equal(d.api.send('call-start'),false);
});
test('snooze changes a reminder, not prescription directions, dose status, or schedule',()=>{
  const d=demo();const before=d.api.state().medication;
  d.api.act('snooze');assert.equal(d.api.state().dose,'pending');
  assert.equal(d.api.state().medication.time,before.time);assert.equal(d.api.state().medication.directions,before.directions);
  enableCalls(d);assert.equal(d.api.send('call-start'),false);
});
test('Live Activity has private, stale, denied and confirmed representations',()=>{
  const d=demo();d.api.go('live');assert.doesNotMatch(d.screen(),/Daily medication/);
  d.api.send('live-state','stale');assert.match(d.screen(),/out of date/);assert.doesNotMatch(d.screen(),/data-action="live-log"/);
  d.api.send('live-state','denied');assert.match(d.screen(),/No Live Activity appears/);assert.doesNotMatch(d.screen(),/class="island-demo/);
  d.api.act('log-save');assert.match(d.screen(),/Ending activity/);
});
test('Live Activity logging opens a confirmation; expand changes only its presentation',()=>{
  const d=demo();d.api.go('live');d.api.act('live-expand');
  assert.equal(d.api.state().live.expanded,true);assert.equal(d.api.state().dose,'pending');
  d.api.act('live-log');assert.equal(d.api.state().view,'today');assert.equal(d.api.state().dose,'pending');
  assert.match(d.sheet(),/Log your morning dose/);
});
test('companion can be hidden without hiding core functionality',()=>{
  const d=demo();d.api.act('companion');assert.doesNotMatch(d.screen(),/aria-label="Farda companion"/);
  assert.match(d.screen(),/Log my dose/);
});
test('setup is simulated and sharing can be revoked locally',()=>{
  const d=demo();d.api.send('scenario','waiting');d.api.go('vial');assert.match(d.screen(),/does not communicate with hardware/);
  for(let i=0;i<4;i++)d.api.act('setup');assert.equal(d.api.state().scenario,'connected');
  d.api.act('share-save');assert.equal(d.api.state().sharing,true);
  d.api.act('share-revoke');assert.equal(d.api.state().sharing,false);
});
test('prototype has no network, audio recording, external font or persistent health-data storage code',()=>{
  assert.doesNotMatch(appCode+modelCode,/\bfetch\s*\(|XMLHttpRequest|WebSocket|localStorage|sessionStorage|getUserMedia|navigator\.bluetooth/);
  assert.doesNotMatch(read('index.html')+read('style.css'),/https?:\/\//);
});
test('referenced source assets exist and standalone embeds every dependency',()=>{
  for(const asset of ['assets/farda-companion.png','../../farda-app/assets/fonts/Outfit-Regular.ttf','../../farda-app/assets/fonts/Outfit-SemiBold.ttf','../../farda-app/assets/images/vial_bottle.png']) assert.equal(existsSync(path.resolve(directory,asset)),true,asset);
  const built=read('farda-navy-mock.html');
  assert.doesNotMatch(built,/src="(?:app|model)\.js"|href="style\.css"|assets\/farda-companion\.png|\.\.\/\.\.\/farda-app/);
  assert.match(built,/data:image\/png;base64,/);assert.match(built,/data:font\/ttf;base64,/);
});
test('core text palette pairs pass WCAG AA normal-text contrast numerically',()=>{
  function luminance(hex) {
    const rgb=hex.match(/\w\w/g).map(x=>parseInt(x,16)/255).map(x=>x<=0.04045?x/12.92:((x+0.055)/1.055)**2.4);
    return .2126*rgb[0]+.7152*rgb[1]+.0722*rgb[2];
  }
  for(const [a,b] of [['142c55','f6f5f0'],['58677d','ffffff'],['ffffff','142c55'],['80500e','f8ecd8']]) {
    const x=luminance(a),y=luminance(b);assert.ok((Math.max(x,y)+.05)/(Math.min(x,y)+.05)>=4.5,a+'/'+b);
  }
});
test('requested reminder cadence is ten minutes before and ten minutes into the window',()=>{
  const d=demo();assert.equal(d.api.state().calls.delay,10);
  enableCalls(d);d.api.send('phase','before');d.api.go('live');
  assert.match(d.screen(),/8:50/);assert.match(d.screen(),/starts in 10 minutes/);
  assert.equal(d.api.send('call-start'),false);
  d.api.send('phase','due');assert.match(d.screen(),/Your routine is ready/);
  assert.equal(d.api.send('call-start'),false);
  d.api.send('phase','call');assert.equal(d.api.send('call-start'),true);
  assert.equal(d.api.state().calls.stage,'ringing');
});
test('the reminder is heard before optional PIN-gated record updates',()=>{
  const d=demo();enableCalls(d);d.api.go('calls');d.api.act('call-start');d.api.act('call-answer');
  assert.match(d.screen(),/Your routine is ready when you are/);
  assert.equal(d.api.state().calls.pinVerified,false);
  assert.match(d.screen(),/Optional private check-in/);
  assert.doesNotMatch(d.screen(),/name="pin"/);
  d.api.act('call-no-answer');assert.equal(d.api.state().calls.stage,'ended');
  assert.equal(d.api.state().dose,'pending');
});
