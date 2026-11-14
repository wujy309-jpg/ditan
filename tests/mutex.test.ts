/**
 * 并发互斥单元测试 —— 碳迹（common/Mutex.ets）
 *
 * 为什么单独一个文件：`tests/logic.test.ts` 里的 55 项是**纯函数**断言，
 * 而互斥锁要验的是「异步临界区的顺序」，两者编译产物、失败语义都不同，
 * 混在一起会让「55 项」这个对外报的数字漂移（PPT / 视频 / 设计方案都引用了 55）。
 * 所以这里独立成 `tools/test-mutex.sh`，对外口径是：
 *   · 逻辑断言 55 项 —— tools/test-logic.sh
 *   · 并发断言  7 项 —— tools/test-mutex.sh
 *
 * 这一份要证明的事（对应手册 B4「三道防线」的第 1 道）：
 *   1. 无锁的「读—让出—写回」会丢失更新（反证：没有锁真的不行）。
 *   2. 加锁后 50 个并发任务全部生效，计数 = 50。
 *   3. 临界区内的并发任务数恒为 1（互斥是真的，不是「碰巧串行」）。
 *   4. 锁不改变执行顺序（先请求先进入）。
 *   5. 临界区抛错时，按 try/finally 释放后队列仍能继续（不会死锁）。
 *
 * 运行：tools/test-mutex.sh
 */
import { Mutex } from './common/Mutex';

declare const process: { exit(code: number): void };

let passed: number = 0;
let failed: number = 0;

function ok(name: string, cond: boolean, detail?: string): void {
  if (cond) {
    passed++;
    console.log(`  \u2713 ${name}`);
  } else {
    failed++;
    console.log(`  \u2717 ${name}${detail ? '  → ' + detail : ''}`);
  }
}

function eq(name: string, actual: unknown, expected: unknown): void {
  const a: string = JSON.stringify(actual);
  const e: string = JSON.stringify(expected);
  ok(name, a === e, `实际 ${a}，期望 ${e}`);
}

/** 让出一次微任务：模拟真实代码里 await 一次异步 IO（KV 读写就是这样） */
function tick(): Promise<void> {
  return Promise.resolve();
}

const N: number = 50;

// ---------------------------------------------------------------------------
// 【1】反证：没有锁，读—让出—写回会丢失更新
// ---------------------------------------------------------------------------
async function withoutLock(): Promise<number> {
  let counter: number = 0;
  const jobs: Promise<void>[] = [];
  for (let i = 0; i < N; i++) {
    jobs.push((async (): Promise<void> => {
      const before: number = counter; // 读
      await tick();                   // 让出：所有任务在这里读到同一个旧值
      counter = before + 1;           // 写回
    })());
  }
  await Promise.all(jobs);
  return counter;
}

// ---------------------------------------------------------------------------
// 【2】加锁：同一个临界区，只是把「读—写」串起来
// ---------------------------------------------------------------------------
interface RunResult {
  counter: number;
  maxInCritical: number;
  order: number[];
}

async function withLock(): Promise<RunResult> {
  const gate: Mutex = new Mutex();
  let counter: number = 0;
  let inCritical: number = 0;
  let maxInCritical: number = 0;
  const order: number[] = [];

  const jobs: Promise<void>[] = [];
  for (let i = 0; i < N; i++) {
    jobs.push((async (): Promise<void> => {
      const release: () => void = await gate.lock();
      inCritical++;
      if (inCritical > maxInCritical) {
        maxInCritical = inCritical;
      }
      try {
        const before: number = counter;
        await tick();
        counter = before + 1;
        order.push(i);
        await tick();
      } finally {
        inCritical--;
        release();
      }
    })());
  }
  await Promise.all(jobs);
  return { counter: counter, maxInCritical: maxInCritical, order: order };
}

// ---------------------------------------------------------------------------
// 【3】临界区抛错：按 try/finally 释放后，后续任务不能被卡死
// ---------------------------------------------------------------------------
async function throwingCase(): Promise<number> {
  const gate: Mutex = new Mutex();
  let done: number = 0;
  const first: Promise<void> = (async (): Promise<void> => {
    const release: () => void = await gate.lock();
    try {
      throw new Error('模拟写积分失败');
    } finally {
      release();
    }
  })().catch((): void => {
    // 吞掉预期内的错误
  });
  const second: Promise<void> = (async (): Promise<void> => {
    const release: () => void = await gate.lock();
    try {
      done++;
    } finally {
      release();
    }
  })();
  await Promise.all([first, second]);
  return done;
}

// ---------------------------------------------------------------------------
async function main(): Promise<void> {
  console.log('\n【1】反证：无锁会丢失更新');
  const lost: number = await withoutLock();
  ok(`无锁 50 并发计数 < 50（实测 ${lost}）`, lost < N, `实际 ${lost}：如果等于 ${N}，说明反证无效，测试本身有问题`);
  eq('无锁并发读到同一个旧值 → 计数为 1', lost, 1);

  console.log('\n【2】加锁后 50 并发全部生效');
  const r: RunResult = await withLock();
  eq(`有锁 50 并发计数 = ${N}`, r.counter, N);
  eq('临界区内并发数恒为 1', r.maxInCritical, 1);
  eq('锁不丢任务（进入顺序长度 = 50）', r.order.length, N);
  ok('锁保持先请求先进入',
    r.order.every((v: number, i: number): boolean => i === 0 || r.order[i - 1] < v),
    `顺序 ${r.order.slice(0, 10).join(',')}…`);

  console.log('\n【3】临界区抛错后队列不死锁');
  eq('抛错释放后，下一个任务仍能进入', await throwingCase(), 1);

  console.log('\n====================================================');
  console.log(`并发测试结果：通过 ${passed} 项，失败 ${failed} 项`);
  console.log('====================================================');
  if (failed > 0) {
    process.exit(1);
  }
}

main();
