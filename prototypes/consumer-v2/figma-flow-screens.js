for(const [key,time]of [['before','8:50'],['due','9:00']]){
const p=await screen(key,'today',true,time,true);const s=roots[key].screen;s.fills=[{type:'GRADIENT_LINEAR',gradientStops:[{position:0,color:{...rgb('#476da4'),a:1}},{position:.5,color:{...rgb('#203d69'),a:1}},{position:1,color:{...rgb('#102449'),a:1}}],gradientTransform:[[1,0,0],[0,1,0]]}];
const clock=F(p,'Lock screen time',346,'VERTICAL',4);clock.counterAxisAlignItems='CENTER';T(clock,'Wednesday, October 14',16,false,'text/inverse');T(clock,time,80,true,'text/inverse');
const pause=F(p,'Wallpaper breathing room',346,'VERTICAL',0);pause.resize(346,180);pause.layoutSizingVertical='FIXED';
const live=F(p,'Live Activity / '+(key==='before'?'Upcoming':'Active'),346,'VERTICAL',14,20,'surface/canvas');radius(live,24);
const head=F(live,'Private activity header',306,'HORIZONTAL',0);head.primaryAxisAlignItems='SPACE_BETWEEN';head.counterAxisAlignItems='CENTER';T(head,'farda.',23,true);const privacy=F(head,'Private preview',116,'HORIZONTAL',5);privacy.counterAxisAlignItems='CENTER';icon(privacy,'lock',14);T(privacy,'Private preview',12,false,'text/secondary');
T(live,key==='before'?'A little heads-up.':'Your routine is ready.',26,true,'text/primary',306);T(live,key==='before'?'Your morning routine starts in 10 minutes.':'9:00 AM · Your routine is active.',14,false,'text/secondary',306);
const timer=F(live,'Time until routine',306,'HORIZONTAL',10);timer.counterAxisAlignItems='CENTER';timer.primaryAxisAlignItems='SPACE_BETWEEN';T(timer,key==='before'?'10:00':'Now',32,true);T(timer,key==='before'?'Until your routine':'Call reminder at 9:10',12,false,'text/secondary');
B(live,key==='before'?'View my routine':'Open & log','Primary',key==='before'?'routine':'checkin',306);
if(key==='due')link(live,'Remind me in 15 minutes','reminders');
const hint=T(p,'Swipe up to open Farda',12,false,'text/inverse',346);hint.textAlignHorizontal='CENTER';
}
{
const p=await screen('incoming','today',true,'9:10',true);p.counterAxisAlignItems='CENTER';p.paddingTop=35;gap(p,18);T(p,'YOUR ROUTINE REMINDER',10,true,'text/inverse');T(p,'Farda',42,true,'text/inverse');T(p,'A gentle ring. Just for you.',16,false,'text/inverse');I(p,'companionWave',150);
const space=F(p,'Call screen breathing room',346,'VERTICAL',0);space.resize(346,170);space.layoutSizingVertical='FIXED';
const buttons=F(p,'Call controls',346,'HORIZONTAL',80);buttons.primaryAxisAlignItems='CENTER';for(const [label,target,col]of [['Decline','today','#b95160'],['Answer','answered','#adc8ed']]){const c=F(buttons,label,80,'VERTICAL',12);c.counterAxisAlignItems='CENTER';const round=F(c,label+' call',68,'HORIZONTAL',0);round.resize(68,68);round.layoutSizingVertical='FIXED';round.cornerRadius=34;round.fills=[{type:'SOLID',color:rgb(col)}];round.counterAxisAlignItems='CENTER';round.primaryAxisAlignItems='CENTER';icon(round,'phone',26,label==='Decline'?'text/inverse':'text/primary');T(c,label,14,false,'text/inverse');links.push([c.id,target]);}
}
{
const p=await screen('answered','today',true,'9:10',true);p.counterAxisAlignItems='CENTER';p.paddingTop=26;T(p,'Farda',38,true,'text/inverse');T(p,'Connected · 00:08',14,false,'text/inverse');I(p,'companionQuiet',100);
const speech=F(p,'Reminder voice script',346,'VERTICAL',12,20,'surface/brand');radius(speech,24);T(speech,'A friendly reminder',22,true,'text/inverse',306);T(speech,'“Hi, this is Farda with the routine reminder you asked for. Open the app when you’re ready.”',18,false,'text/inverse',306);T(speech,'No medication name is spoken in this reminder.',12,false,'text/inverse',306);
const options=F(p,'Optional call choices',346,'VERTICAL',12);B(options,'1   Optional private check-in','Inverse','checkin',346);B(options,'9   Stop this reminder call','Secondary','today',346);T(p,'Your record is still unconfirmed.',12,false,'text/inverse',346);
}
{
const p=await screen('checkin','today');topbar(p);title(p,'Your morning routine','Your record.\nYour choice.','Only you can confirm what happened.');const card1=card(p);badge(card1,'9:00 AM ROUTINE',130);T(card1,'Did you take your dose?',26,true,'text/primary',310);T(card1,'Save an entry for this morning’s routine.',14,false,'text/secondary',310);B(card1,'Yes, I took it · save entry','Primary','confirmed');B(card1,'Remind me in 15 minutes','Secondary','reminders');link(card1,'Not now','today');notice(p,'This saves your own report. You can correct the entry later.');const privacy=card(p);icon(privacy,'lock',24);T(privacy,'Your private check-in',18,true);T(privacy,'Call updates use this same routine record after identity verification.',14,false,'text/secondary',310);link(p,'Back to today','today');
}
{
const p=await screen('confirmed','today');topbar(p);title(p,'A little more breathing room','You’re all set.','Your morning entry is saved.');hero(p,true);const saved=card(p);T(saved,'YOUR MORNING ENTRY',10,true,'text/secondary');T(saved,'Taken · You confirmed',18,true);T(saved,'October 14 · 9:04 AM\nSource: your check-in',14,false,'text/secondary',310);link(saved,'Correct this entry','checkin');T(p,'Ahead of the day',18,true);const next=card(p);smallRow(next,'Evening routine','8:00 PM · Your next reminder','pill','routine');
}
{
const p=await screen('refillHandoff','refills');topbar(p);title(p,'Your next step','Let’s get\nyou ready.','A clear handoff to your usual pharmacy.');const rx=card(p);smallRow(rx,'Daily medication','Rx ending 4821 · Saved by you','pill','routine');const steps=F(rx,'Refill checklist',310,'VERTICAL',14);for(const label of ['Check the prescription label','Confirm pharmacy contact details','Ask about availability and refills']){const r=F(steps,label,310,'HORIZONTAL',10);icon(r,'check',18);T(r,label,14,false,'text/primary',282);}
const pharmacy=card(p);T(pharmacy,'Your pharmacy',18,true);T(pharmacy,'Use the phone number on your label.',14,false,'text/secondary',310);B(pharmacy,'Call my pharmacy','Primary',null,310);link(pharmacy,'I contacted my pharmacy','refills');notice(p,'Opening a contact option does not submit a refill order. Your pharmacy confirms eligibility and timing.',true);link(p,'Back to refill station','refills');
}
await calendarScreen('calendarRefill',16);
const board=await figma.getNodeByIdAsync('2:58');
T(board,'Live Activities · Dynamic Island',22,true);
const islands=F(board,'Compact and expanded islands',720,'HORIZONTAL',28);islands.counterAxisAlignItems='MIN';
const compact=F(islands,'Dynamic Island / Compact',280,'HORIZONTAL',12,16,'surface/deep');radius(compact,24);T(compact,'f.',22,true,'text/inverse');T(compact,'Your routine',14,false,'text/inverse');T(compact,'10:00',16,true,'text/inverse');
const expanded=F(islands,'Dynamic Island / Expanded',360,'VERTICAL',12,20,'surface/deep');radius(expanded,32);T(expanded,'farda.                              Now',18,true,'text/inverse');T(expanded,'Your routine is ready.',22,true,'text/inverse',320);T(expanded,'Call reminder at 9:10, if still unconfirmed.',12,false,'text/inverse',320);B(expanded,'Open & log','Inverse','checkin',320);
changed.push(board.id);
return await finish();
