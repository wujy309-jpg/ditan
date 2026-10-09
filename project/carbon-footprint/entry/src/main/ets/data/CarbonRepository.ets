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
    const options: DistributedStoreOptions = {
      storeId: 'carbon',
      keyPrefix: PREFIX
    };
    const store: DistributedStore = await DistributedStore.create(ctx, options);
    const repo: CarbonRepository = new CarbonRepository(store, ctx);
    CarbonRepository.inst = repo;
    hilog.info(DOMAIN, TAG, 'repository ready, localDeviceId=%{public}s', store.getLocalDeviceId());
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
    const out: T[] = [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].startsWith(prefix)) {
        const v: T | undefined = await this.store.getObject<T>(all[i]);
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
    return await this.addPoints(gain, `记录「${rec.name}」`);
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

  /** 删除一条行为记录 */
  async deleteBehavior(id: string): Promise<void> {
    await this.store.delete(K_BEHAVIOR + id);
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

  /** 记一笔积分流水（正数为获得，负数为兑换消耗） */
  async addPoints(delta: number, reason: string): Promise<PointsEntry> {
    const balance: number = await pointsBalanceOf(this);
    const entry: PointsEntry = {
      id: newId(),
      delta: delta,
      reason: reason,
      ts: Date.now(),
      balanceAfter: balance + delta
    };
    await this.store.putObject<PointsEntry>(K_POINTS + entry.id, entry);
    return entry;
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
