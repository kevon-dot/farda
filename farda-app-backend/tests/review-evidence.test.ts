import { beforeEach, describe, expect, it, vi } from 'vitest';
const db = vi.hoisted(() => ({
  $transaction: vi.fn(), session: { findUnique:vi.fn() },
  prescription:{findUnique:vi.fn(),findMany:vi.fn(),findFirst:vi.fn(),create:vi.fn(),update:vi.fn(),findUniqueOrThrow:vi.fn()},
  dose:{findFirst:vi.fn(),findFirstOrThrow:vi.fn(),findMany:vi.fn(),updateMany:vi.fn()},
  doseCorrection:{create:vi.fn(),findMany:vi.fn()},
}));
vi.mock('@src/lib/prisma',()=>({prisma:db}));
import { createPrescription, listDoses, listPrescriptions, recordDose, changeSchedule } from '@src/routes/PrescriptionRoutes';
import { isAuthenticated } from '@src/middleware/isAuthenticated';
function response() { const res:any={statusCode:200}; res.status=vi.fn((code)=>{res.statusCode=code;return res;});res.json=vi.fn(body=>{res.body=body;return res;}); return res; }
const req = (extra={}) => ({user:{id:'owner-a'},params:{},query:{},body:{},headers:{},...extra}) as any;
describe('review gaps converted to safety assertions', () => {
  beforeEach(()=>{vi.clearAllMocks();db.$transaction.mockImplementation(callback=>callback(db));});
  it.each([createPrescription,listDoses,listPrescriptions,recordDose,changeSchedule])('refuses unauthenticated handler use before querying', async handler=>{const res=response();await handler(req({user:undefined}),res);expect(res.statusCode).toBe(401);expect(db.$transaction).not.toHaveBeenCalled();});
  it('rejects caller-selected identity in create input', async()=>{const res=response();await createPrescription(req({body:{userId:'victim',medicationName:'Example',labelReviewed:true}}),res);expect(res.statusCode).toBe(400);expect(db.prescription.create).not.toHaveBeenCalled();});
  it.each([listDoses,listPrescriptions])('does not enumerate another user through legacy path',async handler=>{const res=response();await handler(req({params:{userId:'victim'}}),res);expect(res.statusCode).toBe(404);expect(db.prescription.findMany).not.toHaveBeenCalled();expect(db.dose.findMany).not.toHaveBeenCalled();});
  it('scopes prescriptions to the authenticated owner',async()=>{db.prescription.findMany.mockResolvedValue([]);const res=response();await listPrescriptions(req(),res);expect(db.prescription.findMany.mock.calls[0][0].where).toEqual({userId:'owner-a',archivedAt:null});});
  it('an owned-looking dose ID alone does not permit updates',async()=>{db.dose.findFirst.mockResolvedValue(null);const res=response();await recordDose(req({params:{id:'foreign'},body:{status:'taken'}}),res);expect(res.statusCode).toBe(404);expect(db.dose.findFirst.mock.calls[0][0].where).toEqual({id:'foreign',userId:'owner-a'});expect(db.dose.updateMany).not.toHaveBeenCalled();});
  it('metadata-only edits preserve status/takenAt and append a correction',async()=>{
    db.dose.findFirst.mockResolvedValue({id:'d1',userId:'owner-a',status:'unconfirmed',takenAt:null,revision:0});
    db.dose.updateMany.mockResolvedValue({count:1});db.dose.findFirstOrThrow.mockResolvedValue({id:'d1',status:'unconfirmed',takenAt:null,note:'Actual note',revision:1});
    const res=response();await recordDose(req({params:{id:'d1'},body:{note:'Actual note'}}),res);
    expect(res.statusCode).toBe(200);expect(db.dose.updateMany.mock.calls[0][0].data).toEqual({note:'Actual note',revision:{increment:1}});expect(db.doseCorrection.create).toHaveBeenCalledOnce();
  });
  it('rejects stale revisions rather than overwriting a concurrent correction',async()=>{db.dose.findFirst.mockResolvedValue({id:'d1',revision:4});const res=response();await recordDose(req({params:{id:'d1'},body:{status:'taken',expectedRevision:3}}),res);expect(res.statusCode).toBe(409);expect(db.dose.updateMany).not.toHaveBeenCalled();});
  it('does not claim or bind arbitrary device IDs on prescription save',async()=>{const res=response();await createPrescription(req({body:{clientRequestId:'stable-draft-1',medicationName:'Example',labelReviewed:true,deviceId:'foreign'}}),res);expect(res.statusCode).toBe(409);expect(db.$transaction).not.toHaveBeenCalled();});
  it('requires a strict bearer token',async()=>{const res=response(),next=vi.fn();await isAuthenticated(req({headers:{authorization:'Bearer token extra'}}),res,next);expect(res.statusCode).toBe(401);expect(db.session.findUnique).not.toHaveBeenCalled();expect(next).not.toHaveBeenCalled();});
  it('expired session is rejected at the exact expiry boundary',async()=>{db.session.findUnique.mockResolvedValue({userId:'a',expiresAt:new Date(0)});const res=response(),next=vi.fn();await isAuthenticated(req({headers:{authorization:'Bearer token'}}),res,next);expect(res.statusCode).toBe(401);expect(next).not.toHaveBeenCalled();});
  it('session database failures do not leak internals or masquerade as logout',async()=>{db.session.findUnique.mockRejectedValue(new Error('password=secret internal SQL'));const res=response();await isAuthenticated(req({headers:{authorization:'Bearer token'}}),res,vi.fn());expect(res.statusCode).toBe(503);expect(JSON.stringify(res.body)).not.toContain('secret');});
});
