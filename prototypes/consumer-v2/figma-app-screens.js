{
const p=await screen('today','today');topbar(p);
const greeting=F(p,'Morning greeting',346,'HORIZONTAL',16);greeting.counterAxisAlignItems='CENTER';
const copy=F(greeting,'Welcome',270,'VERTICAL',4);T(copy,'Good morning, you.',14,false,'text/secondary');T(copy,'Make room\nfor your day.',34,true,'text/primary',270);
const date=F(greeting,'October 14',60,'VERTICAL',2,8,'surface/soft');radius(date,24);date.counterAxisAlignItems='CENTER';T(date,'OCT',10,true);T(date,'14',28,true);
week(p);hero(p);cadence(p);
T(p,'Ahead of the day',18,true);const evening=card(p);smallRow(evening,'Evening routine','8:00 PM · Manual reminder','pill','routine');
T(p,'A little head start',18,true);const refill=card(p);smallRow(refill,'Let’s plan your refill','About 6 days of supply · Estimate','refill','refills');
notice(p,'No vial yet? Your reminders and manual journal work on their own.');T(p,'Your record, not a score. No streaks to keep.',12,false,'text/secondary',346);
}
async function calendarScreen(key,selected){const p=await screen(key,'calendar');topbar(p);title(p,'Your days, at a glance','A rhythm\nthat fits you.');
const cal=F(p,'October 2026 calendar',346,'VERTICAL',12,14,'surface/card');radius(cal,24);
const month=F(cal,'Month navigation',318,'HORIZONTAL',0);month.counterAxisAlignItems='CENTER';month.primaryAxisAlignItems='SPACE_BETWEEN';icon(month,'back',22);T(month,'October 2026',18,true);icon(month,'arrow',22);
const weekdays=F(cal,'Weekday labels',318,'HORIZONTAL',2);for(const d of ['M','T','W','T','F','S','S']){const c=F(weekdays,d,44,'HORIZONTAL',0);c.primaryAxisAlignItems='CENTER';T(c,d,10,false,'text/secondary');}
for(let r=0;r<5;r++){const row=F(cal,'Week '+(r+1),318,'HORIZONTAL',2);for(let col=0;col<7;col++){const d=r*7+col-2;if(d<1||d>31){const blank=F(row,'Outside October',44,'VERTICAL',0);blank.resize(44,44);blank.layoutSizingVertical='FIXED';continue;}const state=d===selected?'Selected':d===12?'Recorded':d===13?'Unconfirmed':d===16?'Refill':'Default';const c=I(row,'day'+state);c.setProperties({[FOUNDATIONS.props['day'+state]]:String(d)});if(d===14)links.push([c.id,'calendar']);if(d===16)links.push([c.id,'calendarRefill']);}}
const legend=F(cal,'Record legend',318,'HORIZONTAL',12);for(const [name,col]of [['Recorded','accent/blue'],['Unconfirmed','text/secondary'],['Refill','text/warm']]){const l=F(legend,name,name==='Unconfirmed'?115:80,'HORIZONTAL',5);l.counterAxisAlignItems='CENTER';dot(l,col,5);T(l,name,10,false,'text/secondary');}
const filters=F(p,'Calendar filters',346,'HORIZONTAL',8);badge(filters,'All',48);badge(filters,'Routine',80);badge(filters,'Refills',75);link(filters,'Today','calendar');
T(p,selected===14?'Wednesday, October 14':'Friday, October 16',14,true);
const entry=card(p);T(entry,selected===14?'9:00 AM · MORNING':'REFILL PLANNING REMINDER',10,true,'text/secondary',310);T(entry,selected===14?'Not yet confirmed':'Check in with your pharmacy',18,true,'text/primary',310);T(entry,selected===14?'You can add or correct your record.':'Your chosen reminder date. Pickup timing comes from your pharmacy.',12,false,'text/secondary',310);link(entry,selected===14?'Add an entry':'Open refill station',selected===14?'checkin':'refills');
const support=F(p,'Friendly calendar note',346,'HORIZONTAL',10);support.counterAxisAlignItems='CENTER';I(support,'companionCalendar',78);T(support,'A blank day isn’t a failure.\nIt’s a record you can review.',12,false,'text/secondary',250);
}
await calendarScreen('calendar',14);
{
const p=await screen('refills','refills');topbar(p);title(p,'One less last-minute thing','The refill\nstation.','Your prescriptions, supply, and next steps. In one calm place.');
const supply=F(p,'Estimated supply',346,'HORIZONTAL',12,20,'surface/soft');radius(supply,24);supply.counterAxisAlignItems='CENTER';const info=F(supply,'Supply summary',204,'VERTICAL',8);T(info,'ESTIMATED SUPPLY',10,true);const num=F(info,'Days remaining',204,'HORIZONTAL',8);num.counterAxisAlignItems='BASELINE';T(num,'6',52,true);T(num,'days',18,false);T(info,'Based on your count and saved daily schedule.',12,false,'text/secondary',204);const bars=F(info,'Supply indicator',204,'HORIZONTAL',4);for(let i=0;i<10;i++)rect(bars,'Supply segment',16,5,i<2?'surface/brand':'border/default',2);vialArt(supply,90);
T(p,'Your refill journey',18,true);const journey=card(p);smallRow(journey,'Daily medication','Your pharmacy · Rx ending 4821','pill','routine');badge(journey,'SELF-MANAGED',118);
for(const [i,h,sub] of [[1,'Plan ahead','Check your label and pharmacy details.'],[2,'Contact pharmacy','Start with your usual pharmacy.'],[3,'Pharmacy review','Eligibility and timing confirmed there.'],[4,'Receive & add supply','Add the count you actually received.']]){const r=F(journey,h,310,'HORIZONTAL',12);const num=F(r,'Step '+i,26,'HORIZONTAL',0,0,i===1?'surface/brand':'surface/soft');num.resize(26,26);num.layoutSizingVertical='FIXED';num.primaryAxisAlignItems='CENTER';num.counterAxisAlignItems='CENTER';radius(num,12);T(num,String(i),12,true,i===1?'text/inverse':'text/secondary');const txt=F(r,'Step copy',272,'VERTICAL',3);T(txt,h,14,true);T(txt,sub,12,false,'text/secondary',272);}
B(journey,'Plan my refill','Primary','refillHandoff');notice(p,'Refills remaining are unverified. Your pharmacy or prescriber confirms eligibility.',true);link(p,'Update my count','refillHandoff');
}
{
const p=await screen('you','you');topbar(p);const intro=F(p,'Your space',346,'HORIZONTAL',14);intro.counterAxisAlignItems='CENTER';const c=F(intro,'Profile heading',222,'VERTICAL',8);T(c,'YOUR SPACE',10,true,'text/secondary');T(c,'A little\nmore you.',34,true,'text/primary',222);I(intro,'companionQuiet',110);
const rows=card(p);smallRow(rows,'Your routine','Medications & reminder times','pill','routine');smallRow(rows,'Reminders that reach you','Live Activities & calls','bell','reminders');smallRow(rows,'Your vial','Connect when you’re ready','vial','vial');smallRow(rows,'Your circle','Share on your terms','circle','circle');
const preferences=card(p);setting(preferences,'A friendly face','Show the Farda companion',true);setting(preferences,'Quiet on your lock screen','Keep medication names private',true);
notice(p,'Your routine belongs to you. You choose what to share and how we remind you.');
}
{
const p=await screen('routine','you');topbar(p);title(p,'Make it yours','Your routine.','Reminder times belong to you. Prescription directions stay as reviewed.');const morning=card(p);smallRow(morning,'Daily medication','Morning routine','pill');const time=F(morning,'Reminder time',310,'HORIZONTAL',20);T(time,'9:00 AM',26,true);link(time,'Edit','reminders');T(morning,'Every day · Los Angeles time',12,false,'text/secondary');T(morning,'Directions copied from your reviewed label.',12,false,'text/secondary',310);
const evening=card(p);smallRow(evening,'Evening routine','8:00 PM · Manual reminder','pill');B(p,'Review a prescription label','Outline',null,346);notice(p,'Scans help with typing. Check unclear directions against your label or with your pharmacy.');const footer=F(p,'Travel note',346,'HORIZONTAL',12);I(footer,'companionCalendar',90);T(footer,'Travel coming up?\nReview your reminder timezone.',14,false,'text/secondary',244);link(p,'Back to your space','you');
}
{
const p=await screen('reminders','you');topbar(p);title(p,'Choose your rhythm','A heads-up.\nThen a real ring.','A little before. Right on time. A call when you want one.');cadence(p);
const preferences=card(p);setting(preferences,'Call reminders','Call 10 minutes after the routine starts',true);setting(preferences,'Live Activities','Start 10 minutes before your routine',true);setting(preferences,'Private previews','Keep medication names off lock screens',true);
const quiet=card(p);T(quiet,'Your quiet hours',18,true);T(quiet,'9:00 PM – 8:00 AM',26,true);T(quiet,'Calls wait during quiet hours. Change this whenever you need.',12,false,'text/secondary',310);link(quiet,'Preview the reminder call','incoming');notice(p,'Calls are optional and use your verified number. Answering a reminder does not change your record.');link(p,'Back to your space','you');
}
{
const p=await screen('vial','you');topbar(p);title(p,'Meet your Farda vial','Good things\nare on the way.','Your app is ready. Connect your vial when it arrives.');const art=F(p,'Vial introduction',346,'HORIZONTAL',26,24,'surface/soft');radius(art,24);art.counterAxisAlignItems='CENTER';vialArt(art,104);const c=F(art,'Hardware arrival',168,'VERTICAL',12);T(c,'A calmer routine,\nin your hands.',22,true,'text/primary',168);badge(c,'COMING SOON',118);
const setup=card(p);T(setup,'When your vial arrives',18,true);for(const [h,sub,glyph]of [['Pair your vial','A guided Bluetooth connection','vial'],['Match the right medication','Check the label before loading','pill'],['Set your routine','Review times and reminders','clock']])smallRow(setup,h,sub,glyph);B(p,'Explore your routine','Primary','routine',346);notice(p,'Movement can prompt a check-in. Only your confirmation creates a taken entry.');
}
{
const p=await screen('circle','you');topbar(p);title(p,'Support that feels right','Your circle.\nYour choice.','Invite someone you trust, with clear choices about what they see.');const circle=F(p,'Private support circle',346,'VERTICAL',14,22,'surface/soft');radius(circle,24);circle.counterAxisAlignItems='CENTER';I(circle,'companionWave',110);T(circle,'A little support, on your terms.',18,true,'text/primary',302);T(circle,'Your circle is empty for now.',14,false,'text/secondary',302);
const options=card(p);T(options,'Choose what you share',18,true);setting(options,'Routine summaries','A view of entries you choose to share',false);setting(options,'Refill reminders','Help planning the next refill',false);setting(options,'A missed confirmation','A nudge only when you enable it',false);B(p,'Invite someone you trust','Primary',null,346);notice(p,'Permissions start off. You can change or revoke access at any time.');link(p,'Back to your space','you');
}
return await finish();
