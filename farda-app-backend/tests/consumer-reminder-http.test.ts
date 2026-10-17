import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import { randomUUID } from 'node:crypto';
import type { Server } from 'node:http';
import twilio from 'twilio';

const provider = vi.hoisted(() => ({ send: vi.fn(), cancel: vi.fn() }));
vi.mock('../src/reminders/voice', async importOriginal => {
  const actual = await importOriginal<typeof import('../src/reminders/voice')>();
  return { ...actual, makeVoiceAdapter: () => ({ enabled: true, send: provider.send, cancel: provider.cancel }) };
});
const databaseUrl = process.env.TEST_DATABASE_URL;
describe.skipIf(!databaseUrl)('consumer HTTP and reminder integration', () => {
  let db:any, server:Server, base:string, reminderService:any;
  const userId=`http-reminders-${randomUUID()}`, otherId=`http-reminders-other-${randomUUID()}`;
  const token=randomUUID(), otherToken=randomUUID(), phone='+15550002345';
  const authToken='synthetic-webhook-secret-only', accountSid=`AC${'1'.repeat(32)}`, origin='https://farda.example';
  const previousEnv:Record<string,string|undefined>={};
  const configured={FARDA_VOICE_ENABLED:'true',FARDA_PUBLIC_BASE_URL:origin,TWILIO_ACCOUNT_SID:accountSid,TWILIO_AUTH_TOKEN:authToken,FARDA_TWILIO_VOICE_FROM:'+15550002346',FARDA_VOICE_ALLOWED_PREFIXES:'+1',FARDA_REMINDER_WORKER_ENABLED:'false',BETTER_AUTH_SECRET:'synthetic-http-test-secret-longer-than-thirty-two'};
  async function call(path:string, method='GET', body?:unknown, bearer:string|null=token) {
    const response=await fetch(`${base}/api${path}`,{method,headers:{'Content-Type':'application/json',...(bearer?{Authorization:`Bearer ${bearer}`}:{})},body:body===undefined?undefined:JSON.stringify(body)});
    const text=await response.text();return {status:response.status,body:text?JSON.parse(text):null};
  }
  async function form(path:string, body:Record<string,string>, signed=false) {
    const response=await fetch(`${base}${path}`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded',...(signed?{'X-Twilio-Signature':twilio.getExpectedTwilioSignature(authToken,`${origin}${path}`,body)}:{})},body:new URLSearchParams(body)});
    return response.status;
  }
  async function seed(offsetMinutes=0) {
    const prescription=await db.prescription.create({data:{userId,medicationName:'Synthetic integration medication',dosageInstructions:'Reviewed fixture text',labelReviewedAt:new Date()}});
    const dose=await db.dose.create({data:{userId,prescriptionId:prescription.id,scheduledFor:new Date(Date.now()+offsetMinutes*60000)}});
    expect((await call(`/reminders/occurrences/${dose.id}/plan`,'POST',{})).status).toBe(200);
    const intents=await db.reminderIntent.findMany({where:{doseId:dose.id}});
    const voice=intents.find((i:any)=>i.channel==='voice');
    return {prescription,dose,intents,voice};
  }
  beforeAll(async()=>{
    process.env.DATABASE_URL=databaseUrl;
    for(const [key,value] of Object.entries(configured)){previousEnv[key]=process.env[key];process.env[key]=value;}
    ({prisma:db}=await import('../src/lib/prisma'));
    await db.user.createMany({data:[{id:userId,phoneNumber:phone,phoneNumberVerified:true},{id:otherId}]});
    await db.session.createMany({data:[{userId,token,expiresAt:new Date(Date.now()+3600000)},{userId:otherId,token:otherToken,expiresAt:new Date(Date.now()+3600000)}]});
    ({reminderService}=await import('../src/reminders/routes'));
    const app=(await import('../src/server')).default;
    server=await new Promise(resolve=>{const listener=app.listen(0,'127.0.0.1',()=>resolve(listener));});
    base=`http://127.0.0.1:${(server.address() as any).port}`;
  },30000);
  afterAll(async()=>{
    if(server) await new Promise<void>(resolve=>server.close(()=>resolve()));
    if(db){await db.user.deleteMany({where:{id:{in:[userId,otherId]}}});await db.$disconnect();}
    for(const [key,value] of Object.entries(previousEnv)) if(value===undefined)delete process.env[key];else process.env[key]=value;
    expect(provider.send).not.toHaveBeenCalled();
  });
  it('mounts preferences and refills behind session authorization',async()=>{
    for(const path of ['/reminders/preferences','/refills','/billing/catalog','/billing/status','/circle/alerts']){
      expect((await call(path,'GET',undefined,null)).status).toBe(401);
      expect((await call(path)).status).toBe(200);
    }
  });
  it('preserves pending reminders after notes/mood but cancels on explicit taken',async()=>{
    const {dose,intents,voice}=await seed();expect(intents.length).toBeGreaterThan(1);
    await db.deliveryAttempt.create({data:{intentId:voice.id,userId,channel:'voice',phoneNumber:phone,state:'reserved'}});
    const note=await call(`/doses/${dose.id}`,'PATCH',{note:'A saved note',mood:'okay',expectedRevision:0});expect(note.status).toBe(200);
    expect((await db.reminderIntent.findMany({where:{doseId:dose.id}})).every((i:any)=>i.state==='pending')).toBe(true);
    const taken=await call(`/doses/${dose.id}`,'PATCH',{status:'taken',expectedRevision:1});expect(taken.status).toBe(200);
    const resolved=await db.reminderIntent.findMany({where:{doseId:dose.id}});
    expect(resolved.filter((i:any)=>i.stage!=='end').every((i:any)=>i.state==='cancelled'&&i.reason==='user_resolved')).toBe(true);
    expect(resolved.find((i:any)=>i.stage==='end')).toMatchObject({channel:'live_activity',state:'pending',reason:null});
    expect((await db.deliveryAttempt.findUnique({where:{intentId:voice.id}})).state).toBe('cancelled');
    expect((await db.doseCorrection.findMany({where:{doseId:dose.id}}))).toHaveLength(2);
    expect((await call(`/doses/${dose.id}`,'PATCH',{status:'taken',expectedRevision:2})).status).toBe(200);
    const repeated=await db.reminderIntent.findMany({where:{doseId:dose.id,stage:'end'}});
    expect(repeated).toHaveLength(1);
    expect(repeated[0]).toMatchObject({channel:'live_activity',state:'pending',reason:null});
  });
  it('does not resurrect a prior call after correcting taken back to unconfirmed',async()=>{
    const {dose,voice}=await seed();
    expect((await call(`/doses/${dose.id}`,'PATCH',{status:'taken',expectedRevision:0})).status).toBe(200);
    expect((await call(`/doses/${dose.id}`,'PATCH',{status:'unconfirmed',expectedRevision:1,reason:'Correction'})).status).toBe(200);
    expect((await call(`/reminders/occurrences/${dose.id}/plan`,'POST',{})).status).toBe(200);
    await reminderService.dispatch(voice.id);
    expect((await db.reminderIntent.findUnique({where:{id:voice.id}})).state).toBe('cancelled');
    expect(await db.deliveryAttempt.count({where:{intentId:voice.id}})).toBe(0);
  });
  it('cancels skipped occurrences but rejects a foreign status change',async()=>{
    const {dose}=await seed();
    expect((await call(`/doses/${dose.id}`,'PATCH',{status:'skipped'},otherToken)).status).toBe(404);
    expect((await db.reminderIntent.findMany({where:{doseId:dose.id}})).every((i:any)=>i.state==='pending')).toBe(true);
    expect((await call(`/doses/${dose.id}`,'PATCH',{status:'skipped',expectedRevision:0})).status).toBe(200);
    const resolved=await db.reminderIntent.findMany({where:{doseId:dose.id}});
    expect(resolved.filter((i:any)=>i.stage!=='end').every((i:any)=>i.state==='cancelled'&&i.reason==='user_resolved')).toBe(true);
    expect(resolved.find((i:any)=>i.stage==='end')).toMatchObject({channel:'live_activity',state:'pending',reason:null});
  });
  it('cancels only the replaced future schedule intents and preserves past history',async()=>{
    const {prescription,dose}=await seed(60*24);
    const past=await db.dose.create({data:{userId,prescriptionId:prescription.id,scheduledFor:new Date(Date.now()-15*60000)}});
    await reminderService.plan(userId,past.id);
    const startDate=new Date(Date.now()+86400000).toISOString().slice(0,10);
    const result=await call(`/prescriptions/${prescription.id}/schedules`,'POST',{recurrence:'daily',times:['09:00'],timezone:'UTC',startDate,durationDays:3});expect(result.status).toBe(201);
    const old=await db.dose.findUnique({where:{id:dose.id}});expect(old.status).toBe('cancelled');expect(old.canceledAt).not.toBeNull();
    expect((await db.reminderIntent.findMany({where:{doseId:dose.id}})).every((i:any)=>i.state==='cancelled'&&i.reason==='schedule_changed')).toBe(true);
    expect((await db.dose.findUnique({where:{id:past.id}})).status).toBe('unconfirmed');
    expect((await db.reminderIntent.findMany({where:{doseId:past.id}})).every((i:any)=>i.state==='pending')).toBe(true);
  });
  it('archives medication and cancels its future reminders in the same operation',async()=>{
    const {prescription,dose}=await seed(60*24);
    expect((await call(`/prescriptions/${prescription.id}`,'DELETE')).status).toBe(204);
    expect((await db.prescription.findUnique({where:{id:prescription.id}})).archivedAt).not.toBeNull();
    expect((await db.dose.findUnique({where:{id:dose.id}})).status).toBe('cancelled');
    expect((await db.reminderIntent.findMany({where:{doseId:dose.id}})).every((i:any)=>i.state==='cancelled'&&i.reason==='prescription_archived')).toBe(true);
  });
  it('rejects unsigned callbacks before bearer auth or any provider-state update',async()=>{
    const {dose,voice}=await seed();const providerId=`CA${'2'.repeat(32)}`;
    const attempt=await db.deliveryAttempt.create({data:{intentId:voice.id,userId,channel:'voice',phoneNumber:phone,state:'submitted',startedAt:new Date(),providerId}});
    const path=`/api/reminders/twilio/${attempt.id}/status`, body={AccountSid:accountSid,To:phone,CallSid:providerId,CallStatus:'completed',SequenceNumber:'1'};
    expect(await form(path,body)).toBe(403);
    expect((await db.deliveryAttempt.findUnique({where:{id:attempt.id}})).providerStatus).toBeNull();
    expect(await form(path,body,true)).toBe(204);
    expect((await db.deliveryAttempt.findUnique({where:{id:attempt.id}})).providerStatus).toBe('completed');
    expect((await db.dose.findUnique({where:{id:dose.id}})).status).toBe('unconfirmed');
    expect((await db.dose.findUnique({where:{id:dose.id}})).takenAt).toBeNull();
  });
});
