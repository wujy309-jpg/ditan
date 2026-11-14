/**
 * CarbonRepository —— 碳数据仓储层
 *
 * 建在 DistributedStore（distributedKVStore）之上，而不是 relationalStore。
 * 原因：创新点 1「超级终端多设备同步」要直接复用 DistributedStore，
 *       两者存储引擎不同，混用会导致后期重写数据层。
 *
 * 键设计（store 已带 'carbon:' 前缀，这里写的都是业务键）：
 *   behavior:<id>   一条低碳行为记录      JSON(BehaviorRecord)
 *   points:<id>     一条积分流水          JSON(PointsEntry)
 *   profile         用户档案（单例）      JSON(Profile)
 *
 * 查询策略：KV 没有 where 子句，用 keys() 取全量再内存排序。
 *           个人级数据量（每天几条到几十条）远未到需要索引的程度。
 */
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ChangeListener,
  DistributedStore,
  DistributedStoreOptions,
  PeerDevice,
  SyncOutcome,
  SyncSnapshot
} from '../common/DistributedStore';
import { Mutex } from '../common/Mutex';
import {
  BehaviorRecord,
  Category,
  categoryLabel,
  defaultProfile,
  newId,
  PointsEntry,
  Profile,
  round2
} from '../model/Models';
import { CarbonInclusiveApi } from './CarbonInclusiveApi';

const DOMAIN: number = 0x0003;
const TAG: string = 'CarbonRepo';

/** store 的键前缀 */
const PREFIX: string = 'carbon:';
/** 业务键前缀 */
const K_BEHAVIOR: string = 'behavior:';
const K_POINTS: string = 'points:';
const K_PROFILE: string = 'profile';
/** 已兑换奖励的归属态（徽章 / 证书），存一个 id 数组 */
const K_OWNED: string = 'owned:rewards';

/** 积分规则：每减排 1 kg CO₂e 得 100 积分 */
export const POINTS_PER_KG: number = 100;

/** 某类目的减排量小计（驱动饼图/柱状图） */
export interface CategoryTotal {
  category: string;
  label: string;
  total: number;
}

/** 导出/备份的数据包结构 */
export interface ExportBundle {
  schema: string;
  exportedAt: number;
  profile: Profile;
  behaviors: BehaviorRecord[];
  points: PointsEntry[];
}

export class CarbonRepository {
  private store: DistributedStore;
  private ctx: common.Context;
  private static inst: CarbonRepository | undefined = undefined;
  private static platformInst: CarbonInclusiveApi | undefined = undefined;
  /** 正在进行中的初始化：并发调用复用同一个 Promise，避免建出两个 store */
  private static pending: Promise<CarbonRepository> | undefined = undefined;
  /** 积分流水的读-改-写互斥 */
  private pointsGate: Mutex = new Mutex();

  private constructor(store: DistributedStore, ctx: common.Context) {
    this.store = store;
    this.ctx = ctx;
  }

  /**
   * 初始化仓储（幂等）。整个应用只应调用一次。
   * 必须在 UI 上下文中拿到 context 后调用。
   */
  static async init(ctx: common.Context): Promise<CarbonRepository> {
    const existing: CarbonRepository | undefined = CarbonRepository.inst;
    if (existing !== undefined) {
      return existing;
    }
    // 两个页面各自 boot 时可能同时调到这里：各自 await create 会建出两个 store，
    // 后完成的覆盖 inst，先完成的那份缓存就成了孤儿。用「进行中的 Promise」收敛。
    const pending: Promise<CarbonRepository> | undefined = CarbonRepository.pending;
    if (pending !== undefined) {
      return pending;
    }
    const job: Promise<CarbonRepository> = CarbonRepository.boot(ctx);
    CarbonRepository.pending = job;
    try {
      return await job;
    } finally {
      CarbonRepository.pending = undefined;
    }
  }

  private static async boot(ctx: common.Context): Promise<CarbonRepository> {
    const options: DistributedStoreOptions = {
      storeId: 'carbon',
      keyPrefix: PREFIX
    };
    const store: DistributedStore = await DistributedStore.create(ctx, options);
    const repo: CarbonRepository = new CarbonRepository(store, ctx);
    CarbonRepository.inst = repo;
    hilog.info(DOMAIN, TAG, 'repository ready, localDeviceId=%{private}s', store.getLocalDeviceId());
    return repo;
  }

  /** 取已初始化的实例；尚未初始化时返回 undefined */
  static get(): CarbonRepository | undefined {
    return CarbonRepository.inst;
  }

  // ------------------------------------------------------------------
  // 内部：按键前缀收敛对象
  // ------------------------------------------------------------------

  private async collect<T>(prefix: string): Promise<T[]> {
    const all: string[] = await this.store.keys();
    const keys: string[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].startsWith(prefix)) {
        keys.push(all[i]);
      }
    }
    // 分批并发读：原来是一条一条 await，记录上百条时首页刷新要等十几个来回。
    // 批大小取 8 —— 够快，又不会一次性把几百个 KV 读同时压给分布式服务。
    const BATCH: number = 8;
    const out: T[] = [];
    for (let from = 0; from < keys.length; from += BATCH) {
      const part: string[] = keys.slice(from, Math.min(keys.length, from + BATCH));
      const loaded: Array<T | undefined> = await Promise.all(
        part.map((k: string): Promise<T | undefined> => this.store.getObject<T>(k))
      );
      for (let j = 0; j < loaded.length; j++) {
        const v: T | undefined = loaded[j];
        if (v !== undefined) {
          out.push(v);
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 基础功能 1：低碳行为核算
  // ------------------------------------------------------------------

  /** 新增一条行为记录，同时按减排量发放积分。返回本次获得的积分流水 */
  async addBehavior(rec: BehaviorRecord): Promise<PointsEntry> {
    await this.store.putObject<BehaviorRecord>(K_BEHAVIOR + rec.id, rec);
    const gain: number = Math.max(1, Math.round(rec.saved * POINTS_PER_KG));
    try {
      return await this.addPoints(gain, `记录「${rec.name}」`);
    } catch (e) {
      // 记录写成功、积分写失败：回滚记录，宁可整笔不成立，
      // 也不要留下「账上有这一条、积分里没有」的哑账（导出对账时无法解释）。
      await this.store.delete(K_BEHAVIOR + rec.id);
      throw e as Error;
    }
  }

  /** 全部行为记录，按录入时间倒序 */
  async listBehaviors(): Promise<BehaviorRecord[]> {
    const list: BehaviorRecord[] = await this.collect<BehaviorRecord>(K_BEHAVIOR);
    list.sort((a: BehaviorRecord, b: BehaviorRecord): number => b.ts - a.ts);
    return list;
  }

  /** 按行为发生日期筛选（含首尾），结果按日期倒序 */
  async behaviorsBetween(from: string, to: string): Promise<BehaviorRecord[]> {
    const all: BehaviorRecord[] = await this.listBehaviors();
    const out: BehaviorRecord[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].date >= from && all[i].date <= to) {
        out.push(all[i]);
      }
    }
    return out;
  }

  /**
   * 删除一条行为记录，并撤销它当初发放的积分。
   *
   * 原实现只删记录、不回滚积分：删掉一条「步行」后，最近记录少一条、
   * 累计减排也变小了，但积分流水里仍留着「记录「步行」+117」，
   * 账本与积分从此永久对不上——这是答辩时最容易被追问的一处。
   *
   * 撤销额取当初发放的规则值（saved × POINTS_PER_KG，最低 1 分，与 addBehavior 同源），
   * 但不超过当前余额：已经花掉的积分追不回来，就把这一笔记成实际扣减额，
   * 保证每条流水的 balanceAfter 算术自洽。
   */
  async deleteBehavior(id: string): Promise<void> {
    const rec: BehaviorRecord | undefined = await this.store.getObject<BehaviorRecord>(K_BEHAVIOR + id);
    await this.store.delete(K_BEHAVIOR + id);
    if (rec === undefined) {
      return;
    }
    const granted: number = Math.max(1, Math.round(rec.saved * POINTS_PER_KG));
    const balance: number = await this.pointsBalance();
    const refund: number = Math.min(granted, Math.max(0, balance));
    if (refund > 0) {
      await this.addPoints(-refund, `撤销「${rec.name}」`);
    }
  }

  /** 累计减排量 kg CO₂e */
  async totalSaved(): Promise<number> {
    const list: BehaviorRecord[] = await this.listBehaviors();
    let sum: number = 0;
    for (let i = 0; i < list.length; i++) {
      sum += list[i].saved;
    }
    return round2(sum);
  }

  /** 按类目汇总减排量，用于饼图/柱状图 */
  async savedByCategory(): Promise<CategoryTotal[]> {
    const cats: string[] = [Category.TRAVEL, Category.ENERGY, Category.RECYCLE, Category.FOOD];
    const list: BehaviorRecord[] = await this.listBehaviors();
    const out: CategoryTotal[] = [];
    for (let c = 0; c < cats.length; c++) {
      let sum: number = 0;
      for (let i = 0; i < list.length; i++) {
        if (list[i].category === cats[c]) {
          sum += list[i].saved;
        }
      }
      const item: CategoryTotal = {
        category: cats[c],
        label: categoryLabel(cats[c]),
        total: round2(sum)
      };
      out.push(item);
    }
    return out;
  }

  // ------------------------------------------------------------------
  // 基础功能 3：碳积分
  // ------------------------------------------------------------------

  /**
   * 记一笔积分流水（正数为获得，负数为兑换消耗）。
   *
   * 两条保护，都是原实现缺的：
   * 1) 余额下限 0。负数 delta 若超出余额，**不落流水**，返回 delta 为 0 的临时流水；
   *    调用方据 `entry.delta === 0` 判定「积分不足」。原先直接写 balanceAfter = 负数，
   *    兑换与撤销叠加时会写出负余额，导出的流水与余额对不上。
   * 2) 串行化。读余额 → 写流水是读-改-写，两个并发的兑换会基于同一份旧余额各写一笔，
   *    余额只减一次、流水却记两次。用进程内互斥把这段临界区锁起来，
   *    覆盖 UI 上的双击/连点（跨设备并发由分布式层负责，不在这里兜）。
   */
  async addPoints(delta: number, reason: string): Promise<PointsEntry> {
    const release: () => void = await this.pointsGate.lock();
    try {
      const balance: number = await pointsBalanceOf(this);
      if (delta < 0 && balance + delta < 0) {
        hilog.warn(DOMAIN, TAG, 'points overdraft rejected: balance=%{public}d delta=%{public}d',
          balance, delta);
        return { id: '', delta: 0, reason: reason, ts: Date.now(), balanceAfter: balance };
      }
      const entry: PointsEntry = {
        id: newId(),
        delta: delta,
        reason: reason,
        ts: Date.now(),
        balanceAfter: balance + delta
      };
      await this.store.putObject<PointsEntry>(K_POINTS + entry.id, entry);
      return entry;
    } finally {
      release();
    }
  }

  /** 当前积分余额 */
  async pointsBalance(): Promise<number> {
    return await pointsBalanceOf(this);
  }

  /** 积分流水，按时间倒序 */
  async listPoints(): Promise<PointsEntry[]> {
    const list: PointsEntry[] = await this.collect<PointsEntry>(K_POINTS);
    list.sort((a: PointsEntry, b: PointsEntry): number => b.ts - a.ts);
    return list;
  }

  // ------------------------------------------------------------------
  // 用户档案
  // ------------------------------------------------------------------

  /** 读取档案；不存在时落一份默认档案 */
  async getProfile(): Promise<Profile> {
    const p: Profile | undefined = await this.store.getObject<Profile>(K_PROFILE);
    if (p === undefined) {
      const def: Profile = defaultProfile();
      await this.store.putObject<Profile>(K_PROFILE, def);
      return def;
    }
    return p;
  }

  async saveProfile(p: Profile): Promise<void> {
    await this.store.putObject<Profile>(K_PROFILE, p);
  }

  // ------------------------------------------------------------------
  // 虚拟奖励的归属状态（徽章 / 证书）
  // ------------------------------------------------------------------

  /**
   * 已兑换过的奖励 id。
   *
   * 为什么需要：reward 原来是纯粹的「花分」操作 —— 兑换完只多一条积分流水，
   * 屏幕上什么也不多，还能反复兑换同一张证书。赛题要求的是「兑换虚拟低碳徽章、
   * 植树证书等奖励」，奖励得有归属态，否则演示时点了看不到东西。
   * 存一个字符串数组，与行为记录一样落在同一个分布式 KV 里，多设备同步时天然一致。
   */
  async listOwned(): Promise<string[]> {
    const raw: string | undefined = await this.store.get(K_OWNED);
    if (raw === undefined || raw.length === 0) {
      return [];
    }
    try {
      const arr: string[] = JSON.parse(raw) as string[];
      return Array.isArray(arr) ? arr : [];
    } catch (e) {
      return [];
    }
  }

  /** 记下一条奖励归属；重复调用不会产生重复项 */
  async markOwned(id: string): Promise<void> {
    const list: string[] = await this.listOwned();
    if (list.indexOf(id) >= 0) {
      return;
    }
    list.push(id);
    await this.store.put(K_OWNED, JSON.stringify(list));
  }

  // ------------------------------------------------------------------
  // 基础功能 5：本地数据管理（备份与报表导出）
  // ------------------------------------------------------------------

  /** 导出全量数据为 JSON 字符串，可直接写文件或分享 */
  async exportJson(): Promise<string> {
    const bundle: ExportBundle = {
      schema: 'carbon-footprint/v1',
      exportedAt: Date.now(),
      profile: await this.getProfile(),
      behaviors: await this.listBehaviors(),
      points: await this.listPoints()
    };
    return JSON.stringify(bundle);
  }

  /** 生成 CSV 格式的统计报表 */
  async exportCsv(): Promise<string> {
    const list: BehaviorRecord[] = await this.listBehaviors();
    const lines: string[] = ['日期,类目,行为,数量,单位,减排量(kgCO2e)'];
    for (let i = 0; i < list.length; i++) {
      const r: BehaviorRecord = list[i];
      lines.push(`${r.date},${categoryLabel(r.category)},${r.name},${r.amount},${r.unit},${r.saved}`);
    }
    return lines.join('\n');
  }

  /** 清空全部数据（谨慎使用） */
  async clearAll(): Promise<void> {
    const all: string[] = await this.store.keys();
    for (let i = 0; i < all.length; i++) {
      await this.store.delete(all[i]);
    }
    hilog.warn(DOMAIN, TAG, 'all data cleared, %{public}d keys', all.length);
  }

  /** 把内容写入应用沙箱的文件，返回完整路径 */
  private writeToSandbox(fileName: string, content: string): string {
    const path: string = `${this.ctx.filesDir}/${fileName}`;
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'backup failed: code=%{public}d msg=%{public}s', err.code, err.message);
      throw new Error(`导出失败：${err.message}`);
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'close backup file failed');
        }
      }
    }
    hilog.info(DOMAIN, TAG, 'backup written: %{public}s (%{public}d bytes)', path, content.length);
    return path;
  }

  /** 基础功能 5：备份碳数据与积分记录到本地文件，返回文件路径 */
  async backupJson(): Promise<string> {
    const json: string = await this.exportJson();
    return this.writeToSandbox('carbon-backup.json', json);
  }

  /** 基础功能 5：导出 CSV 统计报表到本地文件，返回文件路径 */
  async backupCsv(): Promise<string> {
    const csv: string = await this.exportCsv();
    return this.writeToSandbox('carbon-report.csv', csv);
  }

  // ------------------------------------------------------------------
  // 创新点 1：多设备同步（委托给 DistributedStore）
  // ------------------------------------------------------------------

  /** 本机 networkId */
  getLocalDeviceId(): string {
    return this.store.getLocalDeviceId();
  }

  /** 刷新可信对端设备列表 */
  refreshPeers(): PeerDevice[] {
    return this.store.refreshPeers();
  }

  /** 主动触发一次跨设备同步 */
  async syncNow(): Promise<SyncOutcome> {
    return await this.store.sync();
  }

  /**
   * 授权后重新订阅变更；返回是否成功。
   * 见 DistributedStore.retrySubscribe 的说明：订阅只在建库时建立一次，
   * 权限被授予后必须重订阅，否则本次运行会一直是单机模式。
   */
  retrySubscribe(): boolean {
    return this.store.retrySubscribe();
  }

  /** 同步状态快照，直接驱动同步状态面板 */
  snapshot(): SyncSnapshot {
    return this.store.snapshot();
  }

  /** 订阅数据变更（含远端推送） */
  onChange(listener: ChangeListener): void {
    this.store.onChange(listener);
  }

  offChange(listener: ChangeListener): void {
    this.store.offChange(listener);
  }

  // ------------------------------------------------------------------
  // 创新点 3：模拟城市碳普惠平台
  // ------------------------------------------------------------------

  /**
   * 取碳普惠平台接口实例（懒加载，全应用共用一个）。
   * 复用同一个分布式 KV 库，平台侧数据键前缀为 `platform:`。
   */
  platform(): CarbonInclusiveApi {
    let api: CarbonInclusiveApi | undefined = CarbonRepository.platformInst;
    if (api === undefined) {
      api = new CarbonInclusiveApi(this.store);
      CarbonRepository.platformInst = api;
    }
    return api;
  }
}

/** 积分余额计算（抽成自由函数，避免在 addPoints 里递归调用自身） */
async function pointsBalanceOf(repo: CarbonRepository): Promise<number> {
  const list: PointsEntry[] = await repo.listPoints();
  let sum: number = 0;
  for (let i = 0; i < list.length; i++) {
    sum += list[i].delta;
  }
  return sum;
}

