/* Local synthetic-data design model. Not a backend, pharmacy integration or medical device. */
(function (root) {
  'use strict';
  const TODAY = '2026-10-14';
  const fresh = () => ({
    view: 'today', scenario: 'connected', selectedDate: TODAY, month: 9, year: 2026, phase: 'due',
    filter: 'all', dose: 'pending', source: null, snoozed: false, audit: [], occurrence: { time: '09:00' },
    medication: { name: 'Daily medication', time: '09:00', directions: 'Follow your reviewed prescription label.', count: 6, dailyUnits: 1 },
    refill: { stage: 'idle', added: false, quantity: 0 },
    calls: { verified: false, consent: false, enabled: false, delay: 10, quiet: true, attempts: 0, stage: 'idle', pinVerified: false },
    live: { enabled: true, status: 'due', details: false, expanded: false },
    companion: true, sharing: false, setup: 0, labelReviewed: false
  });
  function create() {
    let s = fresh();
    const snapshot = () => JSON.parse(JSON.stringify(s));
    const event = (type, detail) => s.audit.push({ type, detail, at: 'Demo · 9:00 AM' });
    function dispatch(type, value) {
      switch (type) {
        case 'reset': s = fresh(); break;
        case 'view':
          if (!['today', 'calendar', 'refills', 'you', 'routine', 'vial', 'calls', 'live', 'circle'].includes(value)) return false;
          s.view = value; break;
        case 'scenario':
          if (!['connected', 'waiting', 'offline', 'uncertain', 'low'].includes(value)) return false;
          s.scenario = value; break;
        case 'date': {
          if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
          const d = new Date(value + 'T12:00:00Z');
          if (Number.isNaN(d.valueOf()) || d.toISOString().slice(0, 10) !== value) return false;
          s.selectedDate = value; s.month = d.getUTCMonth(); s.year = d.getUTCFullYear(); break;
        }
        case 'month': {
          if (![1, -1].includes(value)) return false;
          const d = new Date(Date.UTC(s.year, s.month + value, 1));
          s.month = d.getUTCMonth(); s.year = d.getUTCFullYear();
          s.selectedDate = d.toISOString().slice(0, 10); break;
        }
        case 'filter': if (!['all', 'routine', 'refills'].includes(value)) return false; s.filter = value; break;
        case 'phase':
          if (!['before', 'due', 'call'].includes(value)) return false;
          s.phase = value;
          if (s.dose === 'pending' && !s.snoozed) s.live.status = value === 'before' ? 'before' : 'due';
          break;
        case 'log':
          if (!['app', 'phone'].includes(value) || s.dose === 'taken') return false;
          if (value === 'phone' && (!s.calls.pinVerified || s.calls.stage !== 'confirm')) return false;
          s.dose = 'taken'; s.source = value === 'phone' ? 'Phone self-report' : 'You'; s.snoozed = false;
          s.live.status = 'confirmed'; s.calls.stage = 'cancelled';
          event('dose-confirmed', s.source); break;
        case 'skip':
          s.dose = 'skipped'; s.source = 'You'; s.live.status = 'ended'; s.calls.stage = 'cancelled';
          event('dose-skipped', 'You'); break;
        case 'undo':
          if (s.dose === 'pending') return false;
          event('dose-corrected', s.dose); s.dose = 'pending'; s.source = null; s.live.status = 'due';
          /* A correction does not silently re-arm an already attempted phone call. */
          break;
        case 'snooze':
          if (s.dose !== 'pending') return false;
          s.snoozed = true; s.live.status = 'snoozed'; s.calls.stage = 'cancelled';
          event('reminder-snoozed', '15 minutes; prescription unchanged'); break;
        case 'medication':
          if (!value || !value.name?.trim() || value.name.length > 80 || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value.time)) return false;
          s.medication.name = value.name.trim(); s.medication.time = value.time;
          event('reminder-edited', 'Future reminder time only'); break;
        case 'label':
          if (!value?.confirmed || !value.name?.trim() || !value.directions?.trim() || value.name.length > 80 || value.directions.length > 500) return false;
          s.labelReviewed = true; event('label-reviewed', 'User reviewed explicit directions; no inference'); break;
        case 'stock':
          if (!Number.isInteger(value) || value < 0 || value > 999) return false;
          s.medication.count = value; event('stock-corrected', value); break;
        case 'refill-handoff':
          if (s.refill.stage !== 'idle') return false;
          s.refill.stage = 'handoff'; event('pharmacy-handoff', 'No request sent by Farda'); break;
        case 'refill-requested':
          if (s.refill.stage !== 'handoff') return false;
          s.refill.stage = 'requested'; event('refill-user-update', 'User reports contacting pharmacy'); break;
        case 'refill-ready':
          if (s.refill.stage !== 'requested') return false;
          s.refill.stage = 'ready'; event('refill-user-update', 'User reports pharmacy said ready'); break;
        case 'refill-collected':
          if (!['requested', 'ready'].includes(s.refill.stage)) return false;
          s.refill.stage = 'collected'; event('refill-user-update', 'User reports receipt'); break;
        case 'refill-add':
          if (s.refill.stage !== 'collected' || s.refill.added || !Number.isInteger(value) || value < 1 || value > 999 || s.medication.count + value > 999) return false;
          s.medication.count += value; s.refill.quantity = value; s.refill.added = true;
          event('stock-added', value); break;
        case 'call-verify': s.calls.verified = true; break; // Demo ONLY: not phone verification.
        case 'call-consent':
          s.calls.consent = value === true;
          if (!s.calls.consent) { s.calls.enabled = false; s.calls.stage = 'cancelled'; }
          break;
        case 'call-enable':
          if (!s.calls.verified || !s.calls.consent) return false;
          s.calls.enabled = true; break;
        case 'call-disable': s.calls.enabled = false; s.calls.consent = false; s.calls.stage = 'cancelled'; break;
        case 'call-delay': if (![10, 20, 30].includes(value)) return false; s.calls.delay = value; break;
        case 'call-start':
          if (!s.calls.enabled || !s.calls.consent || !s.calls.verified || s.calls.attempts >= 1 || s.dose !== 'pending' || s.snoozed || s.phase !== 'call') return false;
          s.calls.attempts += 1; s.calls.stage = 'ringing'; s.calls.pinVerified = false;
          event('call-attempt', 'Simulated only; not a taken dose'); break;
        case 'call-answer': if (s.calls.stage !== 'ringing') return false; s.calls.stage = 'greeting'; break;
        case 'call-private': if (s.calls.stage !== 'greeting') return false; s.calls.stage = 'pin'; break;
        case 'call-pin':
          if (s.calls.stage !== 'pin' || value !== '2468') return false;
          s.calls.pinVerified = true; s.calls.stage = 'menu'; break;
        case 'call-choose-log':
          if (!s.calls.pinVerified || s.calls.stage !== 'menu') return false;
          s.calls.stage = 'confirm'; break;
        case 'call-no-answer':
          if (!['ringing', 'greeting', 'pin', 'menu', 'confirm'].includes(s.calls.stage)) return false;
          s.calls.stage = s.calls.stage === 'ringing' ? 'no-answer' : 'ended';
          event(s.calls.stage === 'no-answer' ? 'call-no-answer' : 'call-ended', 'No dose confirmation'); break;
        case 'live-state':
          if (!['before', 'due', 'snoozed', 'stale', 'denied'].includes(value)) return false;
          s.live.status = value; break; // Scenario viewer, not a notification scheduler.
        case 'live-details': s.live.details = value === true; break;
        case 'live-expand': s.live.expanded = !s.live.expanded; break;
        case 'companion': s.companion = !s.companion; break;
        case 'sharing': s.sharing = value === true; break;
        case 'setup':
          s.setup = Math.min(4, s.setup + 1);
          if (s.setup === 4) s.scenario = 'connected'; break;
        default: return false;
      }
      return true;
    }
    return { snapshot, dispatch };
  }
  root.FardaModel = { create, TODAY };
})(globalThis);
