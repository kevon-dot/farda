import { afterAll, describe, expect, it, vi } from 'vitest';
const lifecycle=vi.hoisted(()=>({stop:vi.fn(),start:vi.fn(),disconnect:vi.fn(),tick:vi.fn(async()=>{}),circle:vi.fn(async()=>({created:0})),close:vi.fn(),once:vi.fn()}));
vi.mock('../src/common/constants/env',()=>({default:{NODE_ENV:'development',HOST:'127.0.0.1',PORT:0}}));
vi.mock('../src/server',()=>({default:{listen:(_port:number,_host:string,callback:()=>void)=>{queueMicrotask(callback);return{close:lifecycle.close,once:lifecycle.once};}}}));
vi.mock('../src/lib/prisma',()=>({prisma:{$disconnect:lifecycle.disconnect}}));
vi.mock('../src/reminders/routes',()=>({reminderService:{tick:lifecycle.tick}}));
vi.mock('../src/circle/routes',()=>({circleAlertService:{materialize:lifecycle.circle}}));
vi.mock('../src/reminders/service',()=>({startReminderWorker:lifecycle.start}));
vi.mock('jet-logger',()=>({default:{info:vi.fn(),err:vi.fn()}}));
const originalListeners={SIGINT:process.listeners('SIGINT'),SIGTERM:process.listeners('SIGTERM')};
afterAll(()=>{for(const signal of ['SIGINT','SIGTERM'] as const)for(const listener of process.listeners(signal))if(!originalListeners[signal].includes(listener))process.removeListener(signal,listener);});
describe('server and worker lifecycle',()=>{
  it('stops accepting HTTP, drains the worker and only then disconnects PostgreSQL once',async()=>{
    let finish:()=>void=()=>{};
    lifecycle.stop.mockReturnValue(new Promise<void>(resolve=>{finish=resolve;}));
    lifecycle.start.mockReturnValue(lifecycle.stop);
    lifecycle.close.mockImplementation((callback:()=>void)=>callback());
    lifecycle.disconnect.mockResolvedValue(undefined);
    const main=await import('../src/main');
    await Promise.resolve();
    expect(lifecycle.start).toHaveBeenCalledOnce();
    await lifecycle.start.mock.calls[0][0].tick();expect(lifecycle.tick).toHaveBeenCalledOnce();expect(lifecycle.circle).toHaveBeenCalledWith(100);
    const stopping=main.shutdown();expect(main.shutdown()).toBe(stopping);
    expect(lifecycle.close).toHaveBeenCalledOnce();expect(lifecycle.stop).toHaveBeenCalledOnce();expect(lifecycle.disconnect).not.toHaveBeenCalled();
    finish();await stopping;expect(lifecycle.disconnect).toHaveBeenCalledOnce();
  });
});
