/* Presentation layer. Every integration in this file is a labelled local simulation. */
(function () {
  'use strict';
  const model = FardaModel.create();
  const el = id => document.getElementById(id);
  const esc = value => String(value).replace(/[&<>"']/g, c => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;' }[c]));
  const paths = {
    home:'<path d="m3 10 9-7 9 7v10H3Z"/><path d="M9 20v-7h6v7"/>',
    calendar:'<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v4m10-4v4M3 11h18m-13 4h1m6 0h1"/>',
    refill:'<path d="M19 7a8 8 0 0 0-13-1L3 9m0-6v6h6m-4 8a8 8 0 0 0 13 1l3-3m0 6v-6h-6"/>',
    user:'<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
    pill:'<path d="m9 3-6 6a6 6 0 0 0 8 8l6-6A6 6 0 0 0 9 3Z" transform="translate(2 2)"/><path d="m8 8 8 8"/>',
    phone:'<path d="m5 3 4 1 1 5-3 2a14 14 0 0 0 6 6l2-3 5 1 1 4c-1 5-7 3-12-2S0 5 5 3Z"/>',
    live:'<rect x="5" y="2" width="14" height="20" rx="4"/><path d="M10 5h4M8 15l3-4 2 3 3-2"/>',
    vial:'<rect x="7" y="3" width="10" height="4" rx="1"/><rect x="5" y="7" width="14" height="15" rx="4"/><path d="M5 12h14"/>',
    arrow:'<path d="m9 5 7 7-7 7"/>',
    back:'<path d="m15 5-7 7 7 7"/>',
    check:'<path d="m5 12 4 4L19 6"/>',
    info:'<circle cx="12" cy="12" r="9"/><path d="M12 11v6m0-10v1"/>',
    clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
    lock:'<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3m-4 4v3"/>',
    plus:'<path d="M12 4v16M4 12h16"/>',
    close:'<path d="m6 6 12 12M6 18 18 6"/>',
    bell:'<path d="M5 17h14l-2-4V9A5 5 0 0 0 7 9v4Zm5 3h4"/>',
    circle:'<circle cx="9" cy="8" r="3"/><path d="M2 20v-2a7 7 0 0 1 14 0v2m0-15a3 3 0 0 1 0 6m3 3a6 6 0 0 1 3 5"/>',
    battery:'<rect x="2" y="7" width="17" height="10" rx="2"/><path d="M22 10v4M5 10v4m3-4v4m3-4v4"/>',
    spark:'<path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5Z"/>'
  };
  const icon = name => '<svg class="icon" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">' + (paths[name] || paths.info) + '</svg>';
  const btn = (text, action, cls) => '<button class="button ' + (cls || '') + '" data-action="' + action + '">' + text + '</button>';
  const routeBtn = (text, view, cls) => '<button class="button ' + (cls || '') + '" data-view="' + view + '">' + text + '</button>';
  const companion = (pose, small) => model.snapshot().companion ? '<span class="companion ' + (pose || '') + (small ? ' companion-mini' : '') + '" role="img" aria-label="Farda companion"></span>' : '';
  const tag = (text, warm) => '<span class="tag ' + (warm ? 'warm' : '') + '">' + text + '</span>';
  const notice = (text, warm) => '<div class="notice ' + (warm ? 'warm' : '') + '">' + icon('info') + '<span>' + text + '</span></div>';
  const topbar = () => '<div class="app-top"><span class="mini-brand">farda.</span><button class="avatar" data-view="you" aria-label="Your settings">YO</button></div>';
  const title = (eyebrow, heading, sub) => '<div class="page-title"><p class="eyebrow">' + eyebrow + '</p><h1>' + heading + '</h1>' + (sub ? '<p>' + sub + '</p>' : '') + '</div>';
  const back = view => '<button class="back" data-view="' + view + '">' + icon('back') + 'Back</button>';
  const time = value => { const [h,m] = value.split(':').map(Number); return (h % 12 || 12) + ':' + String(m).padStart(2,'0') + (h < 12 ? ' AM' : ' PM'); };
  const dateLabel = date => new Date(date + 'T12:00:00Z').toLocaleDateString('en-US', { weekday:'long', month:'long', day:'numeric', timeZone:'UTC' });
  const iso = (y,m,d) => new Date(Date.UTC(y,m,d)).toISOString().slice(0,10);
  const linkRow = (name, desc, glyph, view) => '<button class="link-row" data-view="' + view + '"><span class="pill-icon">' + icon(glyph) + '</span><span class="grow"><h3>' + name + '</h3><p>' + desc + '</p></span>' + icon('arrow') + '</button>';
  const toggle = (label, on, action) => '<button class="toggle ' + (on ? 'on' : '') + '" role="switch" aria-checked="' + on + '" aria-label="' + label + '" data-action="' + action + '"></button>';
  function cadence(s) {
    return '<div class="cadence" aria-label="Your reminder sequence"><span class="eyebrow">YOUR REMINDER RHYTHM</span><p>A heads-up. A moment. A real ring.</p><div class="cadence-track">' +
      [['before','8:50','Live Activity'],['due','9:00','Routine due'],['call','9:' + String(s.calls.delay).padStart(2,'0'),'Call reminder']].map(([phase,clock,label])=>'<button data-phase="' + phase + '" class="' + (s.phase===phase?'active':'') + '" aria-pressed="' + (s.phase===phase) + '"><span class="cadence-dot"></span><strong>' + clock + '</strong><small>' + label + '</small></button>').join('') +
      '</div><p class="cadence-note">Tap to preview time · Calls only when enabled</p></div>';
  }
  function weekStrip() {
    return '<div class="week-strip" aria-label="This week">' + ['M','T','W','T','F','S','S'].map((d,i) => '<button class="' + (i === 2 ? 'selected' : '') + '" data-date="2026-10-' + (12+i) + '" aria-label="' + dateLabel('2026-10-' + (12+i)) + ', open calendar"><span>' + d + '</span><strong>' + (12+i) + '</strong><i class="week-dot"></i></button>').join('') + '</div>';
  }
  function today(s) {
    let headline = 'A moment<br>for your routine.';
    let support = 'Your morning reminder is here.<br>One less thing to hold in mind.';
    let status = '9:00 AM · Awaiting your confirmation';
    if (s.phase === 'before') { headline = 'A little<br>heads-up.'; support = 'Your morning routine is in<br>10 minutes. You’re in good time.'; status = 'Coming up · 9:00 AM'; }
    if (s.phase === 'call') { headline = 'A gentle ring.<br>Just for you.'; support = s.calls.enabled ? 'Your chosen call reminder is<br>ready, if still unconfirmed.' : 'Want a phone reminder?<br>Turn on calls on your terms.'; status = 'Follow-up reminder · Not yet confirmed'; }
    if (s.dose === 'taken') { headline = 'A little more<br>room for your day.'; support = 'Your morning entry is saved.<br>You can always make a correction.'; status = s.source + ' confirmed · 9:00 AM'; }
    if (s.dose === 'skipped') { headline = 'Your routine.<br>Your record.'; support = 'Saved as skipped. Your record<br>can be corrected at any time.'; status = 'You recorded a skipped dose'; }
    if (s.snoozed && s.dose === 'pending') { headline = 'A little<br>breathing room.'; support = 'We’ll remind you again in<br>15 minutes. No plan changes.'; status = 'Reminder snoozed · Not yet confirmed'; }
    let hardware = '';
    if (s.scenario === 'offline') hardware = notice('Your vial hasn’t synced recently. Recent activity is unknown; you can still log it yourself.');
    if (s.scenario === 'uncertain') hardware = notice('Your vial noticed a change. Did you take your dose? A change alone doesn’t confirm that.');
    if (s.scenario === 'low') hardware = notice('Your vial needs charging. Check the Vial page for verified access instructions.', true);
    if (s.scenario === 'waiting') hardware = notice('No vial yet? Your reminders and manual journal work on their own.');
    return topbar() + '<div class="greeting"><div><p>Good morning, you.</p><h1>Make room<br>for your day.</h1></div><div class="date-circle"><span>OCT</span><strong>14</strong></div></div>' + weekStrip() +
      '<section class="hero" aria-label="Current routine"><div class="hero-top"><span class="eyebrow">YOUR MORNING · ' + time(s.occurrence.time) + '</span><h2>' + headline + '</h2><p>' + support + '</p>' + companion(s.dose === 'taken' ? 'quiet-pose' : '') + '</div><div class="hero-bottom"><div class="hero-status"><span class="status-dot"></span>' + status.replace('9:00 AM',time(s.occurrence.time)) + '</div>' +
      (s.dose === 'pending' ? btn(icon('check') + 'Log my dose', 'log', 'white full') + '<div class="button-row">' + btn('Remind in 15 min', 'snooze', 'outline') + btn('More options', 'dose-options', 'outline') + '</div>' : btn('Correct this entry', 'correct', 'white full')) + '</div></section>' +
      hardware + cadence(s) + '<div class="section-head"><h2>Ahead of the day</h2><button class="text-button" data-view="calendar">View calendar</button></div><div class="card small-card"><div class="row"><span class="pill-icon">' + icon('pill') + '</span><div class="grow"><h3>Evening routine</h3><p class="tiny muted">8:00 PM · Manual reminder</p></div>' + tag('UP NEXT') + '</div></div>' +
      '<div class="section-head"><h2>A little head start</h2></div><button class="card small-card refill-link" style="width:100%;text-align:left" data-view="refills"><div class="row"><span class="pill-icon warm">' + icon('refill') + '</span><div class="grow"><h3>Let’s plan your refill</h3><p class="tiny muted">About ' + s.medication.count + ' days of supply · Estimate</p></div>' + icon('arrow') + '</div></button>' +
      '<p class="tiny muted" style="margin-top:16px">Your record, not a score. No streaks to keep.</p>';
  }
  function calendar(s) {
    const days = new Date(Date.UTC(s.year,s.month+1,0)).getUTCDate();
    const offset = (new Date(Date.UTC(s.year,s.month,1)).getUTCDay()+6)%7;
    const month = new Date(Date.UTC(s.year,s.month,1)).toLocaleDateString('en-US',{month:'long',year:'numeric',timeZone:'UTC'});
    let cells = Array.from({length:offset}, () => '<span aria-hidden="true"></span>').join('');
    for (let d=1; d<=days; d++) {
      const date = iso(s.year,s.month,d);
      const mark = date === '2026-10-12' ? 'routine' : date === '2026-10-13' ? 'unknown' : date === '2026-10-16' ? 'refill' : date === FardaModel.TODAY && s.dose === 'taken' ? 'routine' : '';
      const label = dateLabel(date) + (mark === 'routine' ? ', self-reported entry' : mark === 'unknown' ? ', unconfirmed' : mark === 'refill' ? ', refill planning reminder' : '');
      cells += '<button class="day ' + (date === s.selectedDate ? 'selected ' : '') + (date === FardaModel.TODAY ? 'today' : '') + '" data-date="' + date + '" aria-label="' + label + '" aria-pressed="' + (date === s.selectedDate) + '"><span>' + d + '</span>' + (mark ? '<i class="mark ' + mark + '"></i>' : '<i style="height:5px"></i>') + '</button>';
    }
    let agenda = '';
    if (s.filter !== 'refills') {
      const past = s.selectedDate < FardaModel.TODAY, isToday = s.selectedDate === FardaModel.TODAY;
      let status = past ? 'No confirmation saved' : 'Planned reminder';
      let note = past ? 'An empty record doesn’t tell us what happened.' : 'Your reviewed schedule · America/Los_Angeles';
      if (s.selectedDate === '2026-10-12') { status = 'You confirmed your morning entry'; note = 'Self-reported at 9:04 AM · Sample history'; }
      if (isToday) { status = s.dose === 'taken' ? 'Morning entry confirmed' : s.dose === 'skipped' ? 'Recorded as skipped' : 'Morning entry · Not yet confirmed'; note = s.dose === 'taken' ? s.source + ' · Self-report, not verified ingestion' : 'You can add or correct your record.'; }
      agenda += '<div class="timeline-item"><time>' + time(past || isToday ? s.occurrence.time : s.medication.time) + '</time><h3>' + status + '</h3><p>' + note + '</p>' + (isToday ? '<button class="text-button" data-action="' + (s.dose === 'pending' ? 'log' : 'correct') + '">' + (s.dose === 'pending' ? 'Add an entry' : 'Correct this entry') + '</button>' : '<button class="text-button" data-action="history-detail">View record details</button>') + '</div>';
    }
    if (s.filter !== 'routine' && s.selectedDate === '2026-10-16') agenda += '<div class="timeline-item"><time>YOUR REFILL PLANNING REMINDER</time><h3>Check in with your pharmacy</h3><p>Your chosen reminder date, not a promised pickup date.</p><button class="text-button" data-view="refills">Open refill station</button></div>';
    if (!agenda) agenda = '<div class="timeline-item"><h3>A little breathing room.</h3><p>No refill reminder on this sample date.</p></div>';
    return topbar() + title('YOUR DAYS, AT A GLANCE','A rhythm<br>that fits you.','Tap a day. See what’s planned, what’s recorded, and what’s still unknown.') +
      '<section class="card calendar-card" aria-label="Interactive calendar"><div class="month-title"><button class="icon-button" data-month="-1" aria-label="Previous month">' + icon('back') + '</button><h2>' + month + '</h2><button class="icon-button" data-month="1" aria-label="Next month">' + icon('arrow') + '</button></div><div class="weekdays" aria-hidden="true">' + ['M','T','W','T','F','S','S'].map(x=>'<span>'+x+'</span>').join('') + '</div><div class="date-grid" role="group" aria-label="' + month + '">' + cells + '</div><div class="calendar-legend"><span><i class="legend-dot"></i>Recorded</span><span><i class="legend-dot unknown"></i>Unconfirmed</span><span><i class="legend-dot refill"></i>Refill reminder</span></div></section>' +
      '<div class="chips">' + [['all','All'],['routine','Routine'],['refills','Refills']].map(([id,label])=>'<button class="chip ' + (s.filter === id ? 'selected' : '') + '" data-filter="' + id + '" aria-pressed="' + (s.filter === id) + '">' + label + '</button>').join('') + '<button class="text-button" style="margin-left:auto" data-action="calendar-today">Today</button></div><p class="agenda-date">' + dateLabel(s.selectedDate) + '</p><div class="timeline">' + agenda + '</div><div class="row" style="margin-top:23px">' + companion('calendar-pose',true) + '<p class="tiny muted">A blank day isn’t a failure.<br>It’s just a record you can review.</p></div>';
  }
  function refills(s) {
    const stages = ['idle','handoff','requested','ready','collected'];
    const level = stages.indexOf(s.refill.stage);
    let action = btn('Plan my refill ' + icon('arrow'), 'refill-plan', 'full');
    if (s.refill.stage === 'handoff') action = btn('I contacted my pharmacy', 'refill-requested', 'full');
    if (s.refill.stage === 'requested') action = btn('Update pharmacy status', 'refill-update', 'full');
    if (s.refill.stage === 'ready') action = btn('I’ve received my refill', 'refill-collected', 'full');
    if (s.refill.stage === 'collected') action = s.refill.added ? notice(s.refill.quantity + ' tablets added to your inventory. Source: your confirmed count.') : btn('Add the supply I received', 'refill-stock', 'full');
    const statusLabel = {idle:'Ready when you are',handoff:'Next step: your pharmacy',requested:'Contacted · Your update',ready:'Ready · You reported',collected:'Received · You reported'}[s.refill.stage];
    return topbar() + title('ONE LESS LAST-MINUTE THING','The refill<br>station.','Your prescriptions, supply, and next steps. In one calm place.') +
      '<div class="supply-hero"><div class="supply-copy"><span class="eyebrow">ESTIMATED SUPPLY</span><div style="margin-top:12px"><strong>' + s.medication.count + '</strong> <span>days</span></div><p>Based on your count and saved daily schedule. Not a live measurement.</p><div class="supply-bar" aria-hidden="true">' + Array.from({length:10},(_,i)=>'<i class="' + (i<Math.min(10,Math.ceil(s.medication.count/3))?'filled':'') + '"></i>').join('') + '</div></div><img class="vial-img" src="../../farda-app/assets/images/vial_bottle.png" alt="Farda vial concept"></div>' +
      '<div class="section-head"><h2>Your refill journey</h2>' + tag('SELF-MANAGED') + '</div><div class="card"><div class="row"><span class="pill-icon">' + icon('pill') + '</span><div><h3>' + esc(s.medication.name) + '</h3><p class="tiny muted">Your pharmacy · Rx ending 4821</p></div></div><p class="tiny" style="margin-top:16px">' + statusLabel + '</p><ol class="steps">' +
      [['Plan ahead','Check your label and pharmacy details.'],['Contact pharmacy','An app handoff is not a submitted order.'],['Pharmacy review','Timing and eligibility come from your pharmacy.'],['Receive & add supply','Record only what you actually received.']].map(([h,p],i)=>'<li class="' + (level>i?'done':level===i?'current':'') + '"><span class="step-dot">' + (level>i?'✓':i+1) + '</span><div><h3>' + h + '</h3><p>' + p + '</p></div></li>').join('') + '</ol>' + action + '</div>' +
      notice('Refills remaining are unverified. Your pharmacy or prescriber must confirm eligibility.') +
      '<div class="card small-card"><div class="row between"><div><h3>Count look different?</h3><p class="tiny muted">Manual count · Not live sensing</p></div><button class="text-button" data-action="stock">Update count</button></div></div>' +
      (s.refill.added ? '<button class="text-button" data-action="vial-refill" style="margin-top:8px">Next: loading the right vial</button>' : '') +
      '<button class="text-button" data-action="refill-help" style="margin-top:8px">No refills left, or supply running low?</button>';
  }
  function routine(s) {
    return topbar() + back('you') + title('MAKE IT YOURS','Your routine.','Reminder times belong to you. Prescription directions stay as reviewed.') +
      '<div class="card"><div class="row"><span class="pill-icon">' + icon('pill') + '</span><div><h3>' + esc(s.medication.name) + '</h3><p class="tiny muted">Morning routine · Connected vial</p></div></div><div class="setting"><div><h3>' + time(s.medication.time) + '</h3><p>Daily reminder · Los Angeles time</p></div><button class="text-button" data-action="edit-routine">Edit</button></div><p class="tiny muted" style="margin-top:12px">' + esc(s.medication.directions) + '</p></div>' +
      '<div class="card"><div class="row"><span class="pill-icon">' + icon('pill') + '</span><div><h3>Evening routine</h3><p class="tiny muted">8:00 PM · Manual tracking</p></div></div><button class="text-button" data-action="evening-detail" style="margin-top:12px">Review this sample routine</button></div>' +
      '<div style="margin-top:18px">' + btn(icon('plus') + 'Review a prescription label', 'scan', 'outline full') + '</div>' +
      notice('Scans help with typing. Unreadable directions stay blank until you check the label or pharmacy. No generated dosing advice.') +
      '<div class="row">' + companion('calendar-pose',true) + '<p class="tiny muted">Travel coming up?<br>' + '<button class="text-button" data-action="travel">Review your reminder timezone</button></p></div>';
  }
  function you(s) {
    return topbar() + '<div class="profile-banner"><div><p class="eyebrow">YOUR SPACE</p><h1 style="margin-top:8px">A little<br>more you.</h1></div>' + companion('quiet-pose') + '</div>' +
      '<div class="card">' + linkRow('Your routine','Medications, labels & reminder times','pill','routine') + linkRow('Reminders that reach you','Notifications, Live Activities & calls','bell','calls') + linkRow('Your vial',s.scenario === 'waiting' ? 'Connect when you’re ready' : 'Connection, battery & last sync','vial','vial') + linkRow('Your circle','Share on your terms','circle','circle') + '</div><div class="card"><div class="setting"><div><h3>A friendly face</h3><p>Show the Farda companion</p></div>' + toggle('Show the Farda companion',s.companion,'companion') + '</div><div class="setting"><div><h3>Privacy comes first</h3><p>Names hidden on the Lock Screen</p></div>' + icon('lock') + '</div><button class="text-button" data-action="privacy">Your data & privacy controls</button></div>' +
      notice('This concept uses sample data stored only in memory. Refreshing resets it. Nothing is sent anywhere.');
  }
  function vial(s) {
    const text = {
      connected:['A helpful little<br>connection.','Last sample sync · 8:52 AM','72% · Sample battery'],
      waiting:['Good things<br>are on the way.','No hardware connected','Use Farda without a vial'],
      offline:['A little<br>out of touch.','Last sample sync · Yesterday','Battery reading is stale'],
      uncertain:['Let’s check<br>that together.','A weight change needs your review','72% · Sample battery'],
      low:['Time for<br>a little recharge.','Your vial reported low battery','2% · Sample battery']
    }[s.scenario];
    return topbar() + back('you') + title('YOUR FARDA VIAL',text[0],'A helper for your routine. Never the only way to keep your record.') +
      '<div class="card soft-card" style="text-align:center"><img class="vial-img" style="width:145px;height:190px" src="../../farda-app/assets/images/vial_bottle.png" alt="Farda vial concept"><h3 style="margin-top:12px">' + text[1] + '</h3><p class="tiny muted" style="margin-top:6px">' + text[2] + '</p></div>' +
      (s.scenario === 'waiting' ? '<div class="progress-dots">' + Array.from({length:4},(_,i)=>'<i class="' + (i<s.setup?'filled':'') + '"></i>').join('') + '<div class="card"><h3>' + ['Find your vial','Confirm the physical vial','Bind & claim securely','Calibrate and verify'][Math.min(3,s.setup)] + '</h3><p class="tiny muted" style="margin:9px 0">Demo step ' + (s.setup+1) + ' of 4. This does not communicate with hardware.</p>' + btn('Simulate next setup step','setup','full') + '</div>' : '<div style="margin-top:17px">' + btn('Check connection','sync','outline full') + '</div>') +
      notice('A vial change is an observation, not proof you swallowed a dose. You remain in control of the record.') +
      '<button class="text-button" data-action="access">What if my vial won’t open?</button>' +
      '<div class="card small-card"><h3>Hardware still to be verified</h3><p class="tiny muted" style="margin-top:7px">Safe access, pairing, sensing, battery behavior and sync durability require testing on the actual unit.</p></div>';
  }
  function calls(s) {
    if (['ringing','greeting','pin','menu','confirm','no-answer','ended'].includes(s.calls.stage)) return callPreview(s);
    return topbar() + back('you') + title('RIGHT THERE WITH YOU','A heads-up.<br>Then a real ring.','A Live Activity 10 minutes before. Your routine at 9. A reminder call ' + s.calls.delay + ' minutes after.') + cadence(s) +
      '<div class="card soft-card"><div class="row">' + companion('',true) + '<div><h3>Only when you want it.</h3><p class="tiny muted">You choose the timing.<br>You can stop calls at any time.</p></div></div></div>' +
      '<div class="card"><div class="setting"><div><h3>Phone-call reminders</h3><p>' + (s.calls.enabled ? 'Enabled in this demo only' : 'Off until you opt in') + '</p></div>' + toggle('Phone-call reminders',s.calls.enabled,s.calls.enabled?'call-disable':'call-setup') + '</div><div class="setting"><div><h3>Call after ' + s.calls.delay + ' minutes</h3><p>If this routine is still unconfirmed</p></div><button class="text-button" data-action="call-delay">Edit</button></div><div class="setting"><div><h3>Quiet hours</h3><p>9:00 PM–8:00 AM · Los Angeles</p></div>' + icon('clock') + '</div><div class="setting"><div><h3>Private by default</h3><p>No medication names. No recording.</p></div>' + icon('lock') + '</div></div>' +
      '<div class="settings-grid"><div class="card small-card"><strong>1 call</strong><p>Maximum per routine occurrence</p></div><div class="card small-card"><strong>2 per day</strong><p>Proposed account limit, all routines</p></div></div>' +
      (s.calls.enabled ? btn('Preview an eligible call', 'call-start', 'full') : btn('Set up call reminders','call-setup','full')) +
      '<p class="tiny muted" style="margin:13px 0">Prototype: no phone number is contacted. Calls are never an emergency service or a guarantee of delivery.</p>' +
      '<div class="card small-card">' + linkRow('Live Activities','A glanceable reminder on your Lock Screen','live','live') + '</div>';
  }
  function callPreview(s) {
    let content = '';
    if (s.calls.stage === 'ringing') content = '<div class="eyebrow">INCOMING CALL · ILLUSTRATIVE SYSTEM UI</div>' + companion('') + '<h1>Farda</h1><p>Your routine reminder</p><div class="call-script"><p>Caller name and appearance depend on your phone, carrier and caller-branding support.</p></div><div class="call-buttons"><button class="call-button decline" data-action="call-no-answer"><span>' + icon('phone') + '</span>Decline</button><button class="call-button" data-action="call-answer"><span>' + icon('phone') + '</span>Answer demo</button></div>';
    if (s.calls.stage === 'greeting') content = '<p class="eyebrow">YOUR REMINDER · 9:' + String(s.calls.delay).padStart(2,'0') + '</p>' + companion('') + '<h1>A gentle<br>reminder.</h1><div class="call-script"><p>“Hi, this is your automated Farda reminder. Your routine is ready when you are. Open Farda to check in. To make a private update over the phone, press 1. To stop reminder calls, press 9.”</p></div><div class="keypad"><button data-action="call-private"><b>1</b>Optional private check-in</button><button data-action="call-no-answer"><b>×</b>End reminder call</button><button data-action="call-disable"><b>9</b>Stop reminder calls</button></div>';
    if (s.calls.stage === 'pin') content = '<p class="eyebrow">CONNECTED · NOT RECORDED</p><h1 style="margin-top:30px">Hello from<br>Farda.</h1><div class="call-script"><p>“This is your automated Farda reminder. To make a private update, enter your reminder PIN. To stop future reminder calls, press 9.”</p></div><form data-form="call-pin"><label class="form-field">Demo PIN: 2468<input name="pin" inputmode="numeric" maxlength="4" type="password" autocomplete="off" required aria-label="Demo reminder PIN"></label><button class="button white full" type="submit">Continue demo</button><p id="form-error" class="error" role="alert"></p></form><button class="button outline full" style="margin-top:12px" data-action="call-disable">9 · Stop reminder calls</button>';
    if (s.calls.stage === 'menu') content = '<p class="eyebrow">DEMO PIN ACCEPTED · AUTOMATED CALL</p><h1 style="margin-top:30px">Your morning<br>check-in.</h1><div class="call-script"><p>“If you already took your morning dose, press 1 to review a log entry. For another reminder in 15 minutes, press 2. To stop reminder calls, press 9.”</p></div><div class="keypad"><button data-action="call-choose-log"><b>1</b>I already took it</button><button data-action="call-snooze"><b>2</b>Remind me in 15 minutes</button><button data-action="call-disable"><b>9</b>Stop reminder calls</button></div>';
    if (s.calls.stage === 'confirm') content = '<p class="eyebrow">ONE FINAL CHECK</p><h1 style="margin-top:30px">Save that<br>to your record?</h1><div class="call-script"><p>“Press 1 again to record that you took your morning dose. This is your own report. If that is not correct, hang up without saving.”</p></div><div class="keypad"><button data-action="call-log"><b>1</b>Confirm my entry</button><button data-action="call-no-answer"><b>×</b>End without saving</button></div>';
    if (['no-answer','ended'].includes(s.calls.stage)) content = '<p class="eyebrow">CALL ENDED</p>' + companion('quiet-pose') + '<h1>Your day.<br>Your pace.</h1><p>' + (s.calls.stage==='ended'?'Thanks for checking in. No entry was added to your routine.':'No answer was received. Your routine entry is unchanged.') + '</p><div class="call-script"><p>Voicemail is off by default. If separately enabled, it only says: “This is Farda. Please open your app when convenient.”</p></div>' + routeBtn('Back to your day','today','white full');
    return '<div class="call-device">' + content + '<p class="tiny">Local simulation · No phone call is placed</p></div>';
  }
  function live(s) {
    const state = s.live.status;
    const messages = {before:['A little heads-up','Your routine starts in 10 minutes'],due:['Your routine is ready','9:00 AM · Your active reminder'],snoozed:['A little breathing room','Reminder snoozed · 15 minutes'],stale:['Open Farda to check','This update is out of date'],confirmed:['Your entry is saved','Confirmed by you · Ending activity'],ended:['Your entry is saved','Recorded as skipped · Ending activity'],denied:['Regular reminders still work','Live Activities are turned off']};
    const [headline,caption] = messages[state] || messages.due;
    return back('calls') + '<div class="lock-header"><div class="lock-date">' + icon('lock') + '<p style="margin-top:13px">Wednesday, October 14</p></div><div class="lock-time">' + (state==='before'?'8:50':s.phase==='call'?'9:'+String(s.calls.delay).padStart(2,'0'):'9:00') + '</div></div><div class="lock-activity"><div class="row between"><span class="mini-brand">farda.</span><span class="tag">PRIVATE PREVIEW</span></div><h2>' + headline + '</h2><p>' + (s.live.details ? esc(s.medication.name) + ' · ' : '') + caption + '</p>' + (['before','due'].includes(state)?'<div class="live-countdown"><strong>' + (state==='before'?'10:00':'Now') + '</strong><span>' + (state==='before'?'until your routine':s.calls.enabled?'Call reminder at 9:'+String(s.calls.delay).padStart(2,'0'):'Your moment to check in') + '</span></div>':'') +
      (state === 'before' ? '<div style="margin-top:14px">' + routeBtn('View my routine','routine','full') + '</div>' : state === 'denied' ? '<div style="margin-top:14px">' + routeBtn('Open notification settings','calls','secondary full') + '</div>' : state === 'stale' ? '<div style="margin-top:14px">' + routeBtn('Open Farda','today','full') + '</div>' : ['confirmed','ended'].includes(state) ? '<div style="margin-top:14px">' + routeBtn('View my entry','calendar','secondary full') + '</div>' : '<div class="button-row">' + btn('Open & log','live-log') + btn('Remind in 15 min','snooze','secondary') + '</div>') + '</div>' +
      '<p class="lock-caption">' + (state === 'denied' ? 'Fallback notification concept. No Live Activity appears when permission is off.' : 'Lock Screen concept · Names are hidden by default.<br>Logging opens Farda for confirmation.') + '</p>' +
      (state === 'denied' ? '' : '<div class="island-demo ' + (s.live.expanded?'expanded':'') + '"><div class="row"><span class="mini-brand">f.</span><span>' + (state === 'stale'?'Check Farda':state==='confirmed'?'Entry saved':'Your routine') + '</span><span class="island-time">' + (state==='snoozed'?'15 min':state==='before'?'10:00':'Now') + '</span></div>' + (s.live.expanded?'<p>' + caption + '</p>' + routeBtn('Open Farda','today','full'):'') + '</div><button class="text-button" style="color:#e0eafb;display:block;margin:7px auto" data-action="live-expand">' + (s.live.expanded?'Show compact Island':'Show expanded Island') + '</button>') +
      '<div class="chips" aria-label="Preview Live Activity states">' + [['before','10 min before'],['due','Due'],['snoozed','Snoozed'],['stale','Stale'],['denied','Off']].map(([id,label])=>'<button class="chip ' + (id===state?'selected':'') + '" data-live-state="' + id + '" aria-pressed="' + (id===state) + '">' + label + '</button>').join('') + '</div>' + cadence(s) + '<p class="lock-caption">8:50 heads-up → 9:00 routine → 9:' + String(s.calls.delay).padStart(2,'0') + ' optional call.<br>Tap the timeline to preview. No live timer or call runs.</p>';
  }
  function circle(s) {
    return topbar() + back('you') + title('CARE, WITHOUT THE PRESSURE','Your circle.<br>Your choice.','Invite support, not surveillance.') + '<div class="card soft-card"><div class="row">' + companion('quiet-pose',true) + '<div><h3>A little support helps.</h3><p class="tiny muted">Choose what someone can see.<br>Change your mind at any time.</p></div></div></div><div class="card"><h3>' + (s.sharing ? 'Sample supporter' : 'Just you, for now.') + '</h3><p class="tiny muted" style="margin:10px 0">' + (s.sharing ? 'Demo access: routine summary only. No medication names or remote vial controls.' : 'Your routine stays private until you choose to share.') + '</p>' + btn(s.sharing?'Remove sample access':'Preview an invitation',s.sharing?'share-revoke':'share','outline full') + '</div>' + notice('Invitations need a verified recipient, their acceptance, and explicit sharing permissions. This demo does not contact anyone.');
  }
  const views = {today,calendar,refills,routine,you,vial,calls,live,circle};
  const labels = {today:'01 / TODAY',calendar:'02 / CALENDAR',refills:'03 / REFILL STATION',you:'04 / YOUR SPACE',routine:'05 / ROUTINE',vial:'06 / YOUR VIAL',calls:'07 / CALL REMINDERS',live:'08 / LIVE ACTIVITIES',circle:'09 / YOUR CIRCLE'};
  const notes = {
    today:['Less dashboard.<br>More daily companion.','One clear next step, an inviting navy hero, and enough space to breathe. The friendly face adds warmth without judging the person.'],
    calendar:['A calendar you<br>can actually use.','Tap dates, change months and filter routine or refill events. An unconfirmed entry is distinct from a self-reported one. No red wall of “failures.”'],
    refills:['Make refills<br>feel manageable.','Supply awareness, pharmacy handoff, honest status and stock reconciliation. Two separate jobs: get the refill, then add what arrived.'],
    routine:['A routine that<br>remembers your edits.','Review the label, keep a clear schedule, preserve drafts, and change future reminders without rewriting the past.'],
    you:['Consumer-friendly<br>by being considerate.','Readable controls, quiet privacy defaults, optional character artwork, and useful features before the hardware arrives.'],
    vial:['Connection is<br>a state, not a promise.','Show freshness and uncertainty. Manual logging stays available even when the vial is offline, charging or not here yet.'],
    calls:['10 minutes before.<br>10 minutes into it.','A Live Activity introduces the routine, the due state makes the action clear, and an opted-in call follows 10 minutes later. Proactive, useful and personal.'],
    live:['A heads-up.<br>Right on time.','At 8:50, a countdown to your 9:00 routine. At 9:00, a clear active reminder. At 9:10, an optional reminder call. Tap the sequence to feel the flow.'],
    circle:['Support without<br>surveillance.','Choose recipients and scopes. Make revocation visible. A support role must not become permission to control medication access.']
  };
  function inspector(s) {
    const [heading,body] = notes[s.view];
    return '<p class="eyebrow">THE DESIGN INTENT</p><h2>' + heading + '</h2><p>' + body + '</p><div class="note-card"><h3>Try the complete experience</h3><p>Log a dose. Explore October 13 and 16 in the calendar. Walk through a refill. Opt in to a demo call. Preview your Lock Screen.</p>' + routeBtn('Explore the calendar','calendar','outline full') + '</div><div class="note-card"><h3>A real-world state for every day</h3><p>Sample scenarios, not a connected device.</p><div class="scenario-list">' +
      [['connected','Connected'],['waiting','Hardware hasn’t arrived'],['offline','Vial offline'],['uncertain','Uncertain vial activity'],['low','Low battery']].map(([id,label])=>'<button data-scenario="' + id + '" class="' + (s.scenario===id?'selected':'') + '" aria-pressed="' + (s.scenario===id) + '">' + label + (s.scenario===id?' ✓':'') + '</button>').join('') + '</div></div><div class="mini-kicker">ONE FRIEND · THREE EXPRESSIONS</div><div class="companion-trio">' + companion('') + companion('calendar-pose') + companion('quiet-pose') + '</div><div class="spec-row"><span>Primary</span><strong>Deep navy · #142C55</strong></div><div class="spec-row"><span>Typography</span><strong>Your existing Outfit family</strong></div><div class="spec-row"><span>Motion</span><strong>Subtle · Reduced-motion friendly</strong></div><div class="spec-row"><span>Companion</span><strong>Optional · Never punitive</strong></div><p style="font-size:11px;margin-top:13px">This is an interactive HTML design study, not a Flutter implementation. Integrations and native OS surfaces are simulated.</p>';
  }
  function render() {
    const s = model.snapshot();
    el('screen').innerHTML = views[s.view](s);
    el('view-label').textContent = labels[s.view];
    el('phone').classList.toggle('lock-mode',s.view==='live');
    el('bottom-nav').innerHTML = [['today','Today','home'],['calendar','Calendar','calendar'],['refills','Refills','refill'],['you','You','user']].map(([id,label,glyph])=>'<button data-view="' + id + '" class="' + (s.view===id?'active':'') + '"' + (s.view===id?' aria-current="page"':'') + '>' + icon(glyph) + '<span>' + label + '</span></button>').join('');
    el('design-nav').innerHTML = [['today','Today','home'],['calendar','Calendar','calendar'],['refills','Refill station','refill'],['you','Your space','user'],['routine','Routine & labels','pill'],['vial','Vial & setup','vial'],['calls','Phone reminders','phone'],['live','Live Activities','live'],['circle','Your circle','circle']].map(([id,label,glyph],i)=>(i===4?'<p class="nav-group">MORE TO EXPLORE</p>':'') + '<button data-view="' + id + '" class="' + (s.view===id?'active':'') + '"' + (s.view===id?' aria-current="page"':'') + '>' + icon(glyph) + label + '</button>').join('');
    el('inspector').innerHTML = inspector(s);
  }
  let toastTimer, modalTrigger;
  function toast(message) { el('toast').textContent=message; el('toast').hidden=false; clearTimeout(toastTimer); toastTimer=setTimeout(()=>{el('toast').hidden=true;},4300); }
  function open(heading,body) {
    modalTrigger=document.activeElement;
    el('sheet-content').innerHTML='<div class="sheet-header"><h2 id="sheet-title">' + heading + '</h2><button class="icon-button" data-action="close" aria-label="Close dialog">' + icon('close') + '</button></div><div class="sheet-body">' + body + '</div>';
    if (!el('sheet').open) el('sheet').showModal();
  }
  function close() { if(el('sheet').open) el('sheet').close(); if(modalTrigger?.isConnected) modalTrigger.focus(); else el('screen').focus({preventScroll:true}); }
  function go(view) { close(); model.dispatch('view',view); render(); el('screen').focus({preventScroll:true}); }
  function send(type,value) { const ok=model.dispatch(type,value); if(ok) render(); return ok; }
  function act(action) {
    const s=model.snapshot();
    switch(action) {
      case 'reset': close(); send('reset'); toast('The sample experience has been reset.'); break;
      case 'close': close(); break;
      case 'log': case 'live-log':
        if(action==='live-log') send('view','today');
        open('Log your morning dose?','<p>Only confirm if you already took it. This saves your own report, not proof of ingestion.</p><div class="notice"><span>' + esc(s.medication.name) + '<br>' + time(s.occurrence.time) + ' · Today</span></div>' + btn('Yes, save my entry','log-save','full') + btn('Go back','close','outline full')); break;
      case 'log-save': send('log','app'); close(); toast('Your entry is saved. Any pending demo call is cancelled.'); break;
      case 'correct': open('Make a correction','<p>Reopen this entry as unconfirmed? The original entry stays in the audit history. A correction doesn’t automatically schedule another call.</p>' + btn('Reopen as unconfirmed','undo','full')); break;
      case 'undo': send('undo'); close(); toast('Entry reopened. Original report preserved in the demo audit.'); break;
      case 'snooze': if(send('snooze')) toast('Reminder moved by 15 minutes in the demo. Prescription unchanged.'); break;
      case 'dose-options': open('Your routine, your record','<p>Logging a skipped dose is a record of what happened, not advice to skip or change medication.</p>' + btn('Record as skipped','skip','outline full') + routeBtn('Review my routine','routine','outline full')); break;
      case 'skip': send('skip'); close(); toast('Saved as skipped. You can correct it at any time.'); break;
      case 'calendar-today': send('date',FardaModel.TODAY); break;
      case 'history-detail': open(dateLabel(s.selectedDate),'<p>' + (s.selectedDate==='2026-10-12'?'Sample record: self-reported at 9:04 AM. No sensor evidence is attached.':s.selectedDate<FardaModel.TODAY?'No confirmation is available for this sample date. This does not establish whether medication was taken.':'This is a planned reminder, not a completed entry.') + '</p>' + notice('Historical corrections and schedule changes require occurrence-level audit records in the production app.')); break;
      case 'edit-routine': open('Make the reminder yours','<form data-form="routine"><label class="form-field">Display name<input name="name" maxlength="80" value="' + esc(s.medication.name) + '" required></label><label class="form-field">Future reminder time<input name="time" type="time" value="' + s.medication.time + '" required></label><p class="tiny muted">America/Los_Angeles. Changing a reminder does not change prescription directions or past entries.</p><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Save reminder</button></form>'); break;
      case 'scan': open('A scan is a starting point.','<p>Demo scan: directions could not be read. Check the original label or ask your pharmacist. Farda will not fill in the blanks.</p><form data-form="label"><label class="form-field">Medication name<input name="name" maxlength="80" placeholder="As printed on your label" required></label><label class="form-field">Exact label directions<textarea name="directions" maxlength="500" placeholder="Enter the directions you verified" required></textarea></label><label class="check"><input type="checkbox" name="confirmed" required><span>I checked these details against the label or with my pharmacist.</span></label><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Save reviewed draft</button></form>'); break;
      case 'evening-detail': open('An independent routine','<p>This second sample shows that a person may have several medications, with or without separate vials. The production schema needs to support that.</p>' + notice('One medication per vial. Do not mix medications as an app shortcut.')); break;
      case 'travel': open('When your timezone changes','<p>Ask whether future reminders should follow your home timezone or local time. Show the next few occurrences before saving. Don’t silently shift medication directions.</p>' + notice('This is the design specification, not a medication timing recommendation.')); break;
      case 'refill-plan': open('Your pharmacy,<br>your next step.','<p>Review your prescription and contact your pharmacy through its official app, website or phone number. Farda cannot submit a refill in this version.</p><div class="card small-card" style="margin-top:17px"><h3>' + esc(s.medication.name) + '</h3><p class="tiny muted">Rx ending 4821 · Sample only<br>Refills remaining: not verified<br>Pickup timing: ask your pharmacy</p></div>' + btn('Preview pharmacy handoff','refill-handoff','full') + '<p class="tiny muted" style="margin-top:10px">No external website opens and no request is sent in this demo.</p>'); break;
      case 'refill-handoff': send('refill-handoff'); close(); toast('Handoff previewed. Farda has not sent a refill request.'); break;
      case 'refill-requested': send('refill-requested'); toast('Saved your update: you contacted the pharmacy.'); break;
      case 'refill-update': open('What did your pharmacy say?','<p>These are updates you provide, not live pharmacy confirmations.</p>' + btn('They said it’s ready','refill-ready','full') + btn('I already received it','refill-collected','outline full') + btn('Still waiting','close','outline full')); break;
      case 'refill-ready': send('refill-ready'); close(); toast('Saved: you reported the refill is ready.'); break;
      case 'refill-collected': send('refill-collected'); close(); toast('Receipt saved. Inventory has not changed yet.'); break;
      case 'refill-stock': open('Add what you received','<p>Confirm the medication and count before adding supply. Receiving a refill is separate from loading a vial.</p><form data-form="refill-add"><label class="form-field">Tablets received<input name="quantity" type="number" min="1" max="999" step="1" required placeholder="Enter the actual count"></label><label class="check"><input type="checkbox" name="confirmed" required><span>I checked that this is the correct medication and counted the supply received.</span></label><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Confirm supply received</button></form>'); break;
      case 'stock': open('Let’s check your supply','<p>Enter the total count you verified. Estimates are only as reliable as this count and your saved schedule.</p><form data-form="stock"><label class="form-field">Tablets available<input name="count" type="number" min="0" max="999" step="1" value="' + s.medication.count + '" required></label><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Save verified count</button></form>'); break;
      case 'refill-help': open('Let your pharmacy help','<p>Ask your pharmacy or prescriber about eligibility, timing and next steps if there are no refills left or you are concerned about running out. Farda doesn’t recommend changing doses or substitute a medication.</p>'); break;
      case 'vial-refill': open('The right supply.<br>The right vial.','<p>A separate loading flow will verify medication identity, the intended vial and actual loaded count, then verify the sensor reading. One medication per vial.</p>' + notice('Hardware loading, cleaning, compatibility and calibration instructions must come from the validated product instructions. This prototype sends no commands.') + routeBtn('Review my vial','vial','full')); break;
      case 'call-setup': open('Calls, only with your say-so.','<p>Production setup: verify your own phone number, set a reminder PIN, then give separate permission for automated routine calls.</p><form data-form="call-consent"><div class="notice"><span>Demo number: ••• ••• 0142<br>No OTP is sent. No number is contacted.<br>Demo PIN: 2468 — not a production credential.</span></div><label class="check"><input type="checkbox" name="verified" required><span>Simulate successful verification of my own number.</span></label><label class="check"><input type="checkbox" name="consent" required><span>I choose automated Farda routine-reminder calls in this demo. I can turn them off in settings or press 9 during a call. No marketing calls.</span></label><p class="tiny muted">A phone OTP is not permission to call. Quiet hours and limits apply. Real consent wording needs market-specific review before launch.</p><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Enable in this demo</button></form>'); break;
      case 'call-disable': send('call-disable'); close(); toast('Reminder calls turned off. Pending demo call cancelled.'); break;
      case 'call-delay': open('Give yourself some room','<form data-form="call-delay"><label class="form-field">Call only if still unconfirmed<select name="delay">' + [10,20,30].map(n=>'<option value="'+n+'"'+(s.calls.delay===n?' selected':'')+'>After '+n+' minutes</option>').join('') + '</select></label><p class="tiny muted">Default: 10 minutes into your reminder window. This changes reminder timing, not prescription directions. Quiet hours remain 9 PM–8 AM in this concept.</p><p id="form-error" class="error" role="alert"></p><button type="submit" class="button full">Save reminder delay</button></form>'); break;
      case 'call-start': send('phase','call'); if(!send('call-start')) toast('Call not eligible: check opt-in, dose status, snooze or the one-call limit. Reset the demo to try again.'); break;
      case 'call-answer': send('call-answer'); break;
      case 'call-private': send('call-private'); break;
      case 'call-no-answer': send('call-no-answer'); break;
      case 'call-choose-log': send('call-choose-log'); break;
      case 'call-log': if(send('log','phone')) {go('today');toast('Saved as a phone self-report. Not sensor-verified ingestion.');} break;
      case 'call-snooze': send('snooze'); go('today'); toast('Reminder snoozed. No dose was logged.'); break;
      case 'live-expand': send('live-expand'); break;
      case 'companion': send('companion'); break;
      case 'sync': toast(s.scenario==='offline'?'No connection in this scenario. Status remains unknown.':'This is a visual simulation; no hardware sync was attempted.'); break;
      case 'setup': send('setup'); if(model.snapshot().setup===4) toast('Simulated setup complete. Actual sequence awaits hardware validation.'); break;
      case 'access': open('Medication access comes first.','<p>Farda needs a verified access path for a dead battery, unavailable phone, lost connection or a jam. The supplied firmware documents do not prove that every failure is recoverable.</p>' + notice('Do not display an invented unlock procedure. Hardware-specific instructions must be validated before this ships.')); break;
      case 'privacy': open('Private by design','<p>Production controls should include export, correction, account deletion, retention choices, notification privacy, and immediate sharing revocation.</p><div class="card small-card" style="margin-top:15px"><h3>This prototype</h3><p class="tiny muted">Synthetic data only. No storage, analytics, tracking, API calls or audio recording. Refresh to reset.</p></div>'); break;
      case 'share': open('Share just enough','<p>Preview permission for a sample supporter to see a routine summary only. No medication names, remote locking or automatic emergency escalation.</p>' + btn('Simulate accepted invitation','share-save','full')); break;
      case 'share-save': send('sharing',true); close(); toast('Sample permission added. No invitation was sent.'); break;
      case 'share-revoke': send('sharing',false); toast('Sample access removed.'); break;
    }
  }
  function submit(form,values) {
    let ok=false, message='';
    if(form==='routine') {ok=model.dispatch('medication',values);message='Your future reminder was updated. Past entries are unchanged.';}
    if(form==='label') {ok=model.dispatch('label',values);message='Reviewed draft saved. No schedule was inferred or activated.';}
    if(form==='stock') {ok=String(values.count).trim()!=='' && model.dispatch('stock',Number(values.count));message='Your verified supply count is saved.';}
    if(form==='refill-add') {ok=values.confirmed===true && model.dispatch('refill-add',Number(values.quantity));message='Received supply added once. Vial loading still needs its own confirmation.';}
    if(form==='call-consent' && values.verified===true && values.consent===true) {model.dispatch('call-verify');model.dispatch('call-consent',true);ok=model.dispatch('call-enable');message='Calls enabled in the demo only. No phone was contacted.';}
    if(form==='call-delay') {ok=model.dispatch('call-delay',Number(values.delay));message='Your reminder delay is saved.';}
    if(form==='call-pin') {ok=model.dispatch('call-pin',values.pin);message='Demo PIN accepted.';}
    if(ok) {render();close();toast(message);} else if(el('form-error')) el('form-error').textContent='Please check the required details. Nothing has been saved.';
    return ok;
  }
  document.addEventListener('click',event=>{
    const target=event.target.closest('button, a[data-view]');
    if(!target) return;
    const d=target.dataset;
    if(d.view) {event.preventDefault();go(d.view);}
    else if(d.action) act(d.action);
    else if(d.date) {send('date',d.date);if(model.snapshot().view!=='calendar')go('calendar');else document.querySelector('[data-date="'+d.date+'"]')?.focus({preventScroll:true});}
    else if(d.month) send('month',Number(d.month));
    else if(d.filter) send('filter',d.filter);
    else if(d.scenario) {send('scenario',d.scenario);if(!['today','vial'].includes(model.snapshot().view))go('today');}
    else if(d.phase) {
      send('phase',d.phase);
      if(d.phase==='before'||d.phase==='due')go('live');
      else {go('calls');if(model.snapshot().calls.enabled)act('call-start');else toast('At the call step, a reminder follows only if you have opted in.');}
    }
    else if(d.liveState) { if(['before','due'].includes(d.liveState))send('phase',d.liveState);send('live-state',d.liveState); }
  });
  document.addEventListener('submit',event=>{
    const form=event.target.dataset.form;
    if(!form)return;
    event.preventDefault();
    const data=Object.fromEntries(new FormData(event.target).entries());
    for(const key of ['confirmed','verified','consent'])data[key]=data[key]==='on';
    submit(form,data);
  });
  document.addEventListener('keydown',event=>{
    const date=event.target.dataset?.date;
    if(!date || model.snapshot().view!=='calendar')return;
    const delta={ArrowLeft:-1,ArrowRight:1,ArrowUp:-7,ArrowDown:7}[event.key];
    if(delta===undefined)return;
    event.preventDefault();
    const d=new Date(date+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+delta);
    const next=d.toISOString().slice(0,10);send('date',next);
    document.querySelector('[data-date="'+next+'"]')?.focus({preventScroll:true});
  });
  window.fardaDemo={go,act,send,submit,render,state:model.snapshot};
  render();
})();
