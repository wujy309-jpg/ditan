/**
 * 进程内互斥（异步锁）—— 给「读-改-写」型异步临界区排队。
 *
 * 为什么需要：分布式 KV 没有事务，积分记账（读余额 → 校验 → 写流水）与
 * 权益兑换（读账户/库存 → 校验 → 写回）都是典型的读-改-写，
 * 两次并发调用会基于同一份旧值各写一次：余额只减一次、流水却记两笔。
 *
 * 边界：只保证同一进程内的先后顺序。跨设备并发由分布式层负责，
 * 那边同样没有事务，属于工程里已声明的不做项（两台真机同时兑换仍可能超卖）。
 *
 * 用法（必须 try/finally，忘记 release 会死锁）：
 *   const release: () => void = await gate.lock();
 *   try { ... } finally { release(); }
 */
export class Mutex {
  /** 队尾：每个 lock 把自己的 Promise 接到队尾，前一个 release 后才轮到它 */
  private tail: Promise<void> = Promise.resolve();

  async lock(): Promise<() => void> {
    let release: () => void = () => {
    };
    const next: Promise<void> = new Promise<void>((resolve: () => void) => {
      release = resolve;
    });
    const prev: Promise<void> = this.tail;
    this.tail = next;
    await prev;
    return release;
  }
}
