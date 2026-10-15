import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest';
import type { Server } from 'node:http';
import { randomUUID } from 'node:crypto';

const sms = vi.hoisted(() => ({ send:vi.fn(), verify:vi.fn() }));
vi.mock('@src/services/twilioService', () => ({ sendSmsOTP:sms.send, verifyTwilioOTP:sms.verify }));
const testUrl = process.env.TEST_DATABASE_URL;
// A test database must be explicitly provided. No migrations or general table
// truncation occur here; each test deletes only its own synthetic account IDs.
describe.skipIf(!testUrl)('PostgreSQL HTTP contract and persistence', () => {
  let prisma:any, server:Server, base:string;
  const ownedIds:string[]=[];
  const tokens = [`test-a-${randomUUID()}`,`test-b-${randomUUID()}`];
  let a:string,b:string,rx:string,dose:string;
  const tomorrow = new Date(Date.now()+86400000).toISOString().slice(0,10);
  const draft = { clientRequestId:randomUUID(), medicationName:'Synthetic medication',dosageInstructions:'Directions transcribed for a test',labelReviewed:true,schedule:{recurrence:'daily',times:['09:00'],timezone:'America/Los_Angeles',startDate:tomorrow,durationDays:7} };
  async function call(path:string, token:string|null=tokens[0], method='GET', body?:unknown) {
    const response=await fetch(`${base}/api${path}`,{method,headers:{...(token?{Authorization:`Bearer ${token}`} : {}),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body)});
    return { status:response.status, body:response.status===204?null:await response.json() as any };
  }
  beforeAll(async()=>{
    process.env.DATABASE_URL=testUrl;
    process.env.BETTER_AUTH_SECRET='synthetic-test-secret-only-at-least-thirty-two-characters';
    process.env.BETTER_AUTH_URL='http://localhost:8000';
    ({prisma}=await import('@src/lib/prisma'));
    a=`integration-a-${randomUUID()}`;b=`integration-b-${randomUUID()}`;ownedIds.push(a,b);
    await prisma.user.createMany({data:[{id:a,name:'Synthetic A'},{id:b,name:'Synthetic B'}]});
    await prisma.session.createMany({data:[a,b].map((userId,i)=>({id:randomUUID(),userId,token:tokens[i],expiresAt:new Date(Date.now()+3600000)}))});
    const app=(await import('@src/server')).default;
    server=await new Promise<Server>(resolve=>{const s=app.listen(0,'127.0.0.1',()=>resolve(s));});
    base=`http://127.0.0.1:${(server.address() as any).port}`;
  },30000);
  afterAll(async()=>{
    if(server) await new Promise<void>((resolve,reject)=>server.close(error=>error?reject(error):resolve()));
    if(prisma){await prisma.user.deleteMany({where:{id:{in:ownedIds}}});await prisma.$disconnect();}
  });
  it('rejects missing sessions across prescriptions, history and OCR',async()=>{
    for(const path of ['/prescriptions','/doses','/prescriptions/ocr/user/foreign']) expect((await call(path,null)).status).toBe(401);
    expect((await call('/prescriptions/ocr/extract',null,'POST',{})).status).toBe(401);
  });
  it('creates two independent medications without replacing the first',async()=>{
    const first=await call('/prescriptions',tokens[0],'POST',draft);expect(first.status).toBe(201);rx=first.body.data.id;
    const second=await call('/prescriptions',tokens[0],'POST',{clientRequestId:randomUUID(),medicationName:'Second medication',labelReviewed:true});expect(second.status).toBe(201);expect(second.body.data.id).not.toBe(rx);
    expect((await call('/prescriptions')).body.data).toHaveLength(2);
    const list=await call('/doses');dose=list.body.data.find((d:any)=>d.prescriptionId===rx).id;
  });
  it('prevents another real session from reading and mutating owner records',async()=>{
    expect((await call('/prescriptions',tokens[1])).body.data).toEqual([]);
    expect((await call(`/prescriptions/ocr/user/${a}`,tokens[1])).status).toBe(404);
    expect((await call(`/prescriptions/${rx}`,tokens[1],'PATCH',{labelReviewed:true,medicationName:'Foreign write'})).status).toBe(404);
    expect((await call(`/prescriptions/${rx}/schedules`,tokens[1],'POST',draft.schedule)).status).toBe(404);
    expect((await call(`/doses/${dose}`,tokens[1],'PATCH',{status:'taken'})).status).toBe(404);
    expect((await call(`/doses/${dose}/history`,tokens[1])).status).toBe(404);
  });
  it('returns the same medication and no new reminders for an identical retry',async()=>{
    const before=await prisma.dose.count({where:{prescriptionId:rx}});
    const retry=await call('/prescriptions',tokens[0],'POST',Object.fromEntries(Object.entries(draft).reverse()));
    expect(retry.status).toBe(200);expect(retry.body.data.id).toBe(rx);expect(retry.body.data.requestHash).toBeUndefined();
    expect(await prisma.prescription.count({where:{userId:a,clientRequestId:draft.clientRequestId}})).toBe(1);
    expect(await prisma.dose.count({where:{prescriptionId:rx}})).toBe(before);
  });
  it('rejects key reuse with a changed draft without changing the original',async()=>{
    const conflict=await call('/prescriptions',tokens[0],'POST',{...draft,medicationName:'Changed draft'});
    expect(conflict.status).toBe(409);expect(conflict.body.code).toBe('idempotency_conflict');
    expect((await prisma.prescription.findUnique({where:{id:rx}})).medicationName).toBe(draft.medicationName);
  });
  it('scopes the same client request key to each authenticated account',async()=>{
    const secondOwner=await call('/prescriptions',tokens[1],'POST',{...draft,schedule:undefined});
    expect(secondOwner.status).toBe(201);expect(secondOwner.body.data.id).not.toBe(rx);
    expect(secondOwner.body.data.userId).toBe(b);
  });
  it('rejects a create without a stable retry key before writing',async()=>{
    const {clientRequestId,...withoutKey}=draft;
    const before=await prisma.prescription.count({where:{userId:a}});
    expect((await call('/prescriptions',tokens[0],'POST',withoutKey)).status).toBe(400);
    expect(await prisma.prescription.count({where:{userId:a}})).toBe(before);
  });
  it.skipIf(process.env.TEST_DATABASE_SINGLE_CONNECTION === 'true')('commits one medication and one schedule for simultaneous matching creates',async()=>{
    const concurrent={...draft,clientRequestId:randomUUID()};
    const results=await Promise.all([call('/prescriptions',tokens[0],'POST',concurrent),call('/prescriptions',tokens[0],'POST',concurrent)]);
    expect(results.map(r=>r.status).sort()).toEqual([200,201]);expect(results[0].body.data.id).toBe(results[1].body.data.id);
    const record=await prisma.prescription.findUnique({where:{userId_clientRequestId:{userId:a,clientRequestId:concurrent.clientRequestId}}});
    expect(await prisma.scheduleVersion.count({where:{prescriptionId:record.id}})).toBe(1);
    expect(await prisma.dose.count({where:{prescriptionId:record.id}})).toBe(7);
  });
  it('round-trips notes independently and preserves correction history',async()=>{
    const note=await call(`/doses/${dose}`,tokens[0],'PATCH',{note:'Real saved note',mood:'okay',expectedRevision:0});
    expect(note.status).toBe(200);expect(note.body.data.status).toBe('unconfirmed');expect(note.body.data.takenAt).toBeNull();
    const taken=await call(`/doses/${dose}`,tokens[0],'PATCH',{status:'taken',expectedRevision:1});expect(taken.status).toBe(200);
    const corrected=await call(`/doses/${dose}`,tokens[0],'PATCH',{status:'unconfirmed',reason:'Tapped by mistake',expectedRevision:2});expect(corrected.status).toBe(200);expect(corrected.body.data.note).toBe('Real saved note');
    const history=await call(`/doses/${dose}/history`);expect(history.body.data).toHaveLength(3);expect(history.body.data[1].after.status).toBe('taken');expect(history.body.data[2].before.status).toBe('taken');
  });
  it.skipIf(process.env.TEST_DATABASE_SINGLE_CONNECTION === 'true')('permits at most one concurrent write at the same revision',async()=>{
    const results=await Promise.all(['one','two'].map(note=>call(`/doses/${dose}`,tokens[0],'PATCH',{note,expectedRevision:3})));
    expect(results.map(r=>r.status).sort()).toEqual([200,409]);
    expect(await prisma.doseCorrection.count({where:{doseId:dose}})).toBe(4);
  });
  it('preserves past unconfirmed rows when a future schedule changes',async()=>{
    const past=await prisma.dose.create({data:{userId:a,prescriptionId:rx,scheduledFor:new Date(Date.now()-86400000),status:'unconfirmed'}});
    const oldCount=await prisma.dose.count({where:{prescriptionId:rx}});
    const result=await call(`/prescriptions/${rx}/schedules`,tokens[0],'POST',{...draft.schedule,times:['10:30']});expect(result.status).toBe(201);
    expect((await prisma.dose.findUnique({where:{id:past.id}})).status).toBe('unconfirmed');
    expect(await prisma.dose.count({where:{prescriptionId:rx}})).toBe(oldCount+7);
    expect(await prisma.dose.count({where:{prescriptionId:rx,status:'cancelled'}})).toBe(7);
    expect(await prisma.scheduleVersion.count({where:{prescriptionId:rx}})).toBe(2);
  });
  it('rolls back a newly saved medication when schedule generation fails',async()=>{
    const before=await prisma.prescription.count({where:{userId:a}});
    const result=await call('/prescriptions',tokens[0],'POST',{...draft,clientRequestId:randomUUID(),schedule:{...draft.schedule,startDate:'2000-01-01',durationDays:1}});expect(result.status).toBe(422);
    expect(await prisma.prescription.count({where:{userId:a}})).toBe(before);
  });
  it('does not report successful OTP delivery after provider failure',async()=>{
    sms.send.mockRejectedValueOnce(new Error('Synthetic provider outage secret must be redacted'));
    const result=await call('/auth/send-otp',null,'POST',{phoneNumber:'+15550001001'});expect(result.status).toBe(503);expect(JSON.stringify(result.body)).not.toContain('secret');
  });
  it('creates a real shared session from simulated verified OTP and revokes it',async()=>{
    sms.verify.mockResolvedValueOnce({status:'approved'});
    const login=await call('/auth/verify-otp',null,'POST',{phoneNumber:'+15550001002',code:'123456'});
    expect(login.status).toBe(200);expect(login.body.token).toBeTypeOf('string');ownedIds.push(login.body.user.id);
    const token=login.body.token;expect((await call('/auth/session',token)).body.data.user.id).toBe(login.body.user.id);
    expect((await call('/auth/sign-out',token,'POST',{})).status).toBe(204);expect((await call('/prescriptions',token)).status).toBe(401);
  });
  it('expires a real database session without a local cache granting access',async()=>{
    await prisma.session.update({where:{token:tokens[1]},data:{expiresAt:new Date(0)}});expect((await call('/doses',tokens[1])).status).toBe(401);
  });
});
