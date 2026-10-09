/**
 * DistributedStore —— 可复用的鸿蒙分布式键值存储封装
 *
 * 把「分布式 KV 读写 + 跨设备同步 + 时间戳冲突处理 + 同步状态统计」四件事
 * 封装成一个业务层可以直接调用的类，避免每个页面重复写分布式样板代码。
 *
 * 适用场景：
 *   · 赛题一：收藏 / 笔记 / 学习进度的多设备自动同步（主要功能第 3 条）
 *   · 赛题二：超级终端多设备同步、家庭碳积分合并统计（创新拓展第 1 条）
 *
 * 设计要点：
 *   1. 所有值以「信封」形式落库：{ payload, ts, origin }
 *      信封让「最新时间戳优先」的冲突策略可以真正落地，而不是空谈。
 *   2. 冲突计数真实可信：收到远端变更时，若本机影子副本的时间戳更新，
 *      则判定为一次冲突并回写本机版本，conmlictCount 自增。
 *   3. snapshot() 直接返回驱动「同步状态可视化面板」所需的全部字段。
 *
 * 注意：跨设备同步需要两台设备登录同一华为账号、完成设备认证并处于同一局域网，
 *      且应用已获得 ohos.permission.DISTRIBUTED_DATASYNC（user_grant，需运行时申请）。
 */
import { distributedKVStore } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0002;
const TAG: string = 'DistributedStore';

/** 等待 syncComplete 回调的超时时间（毫秒） */
const SYNC_TIMEOUT_MS: number = 15000;

/** 分布式 KV「键不存在」的业务错误码（实测值） */
const KV_NOT_FOUND: number = 15100004;

// ---------------------------------------------------------------------------
// 对外类型
// ---------------------------------------------------------------------------

/** 可信对端设备 */
export interface PeerDevice {
  deviceId: string;
  deviceName: string;
  deviceType: string;
}

/** 一次同步的结果 */
export enum SyncOutcome {
  /** 全部对端同步成功 */
  SUCCESS = 'SUCCESS',
  /** 部分对端成功 */
  PARTIAL = 'PARTIAL',
  /** 全部失败 */
  FAILED = 'FAILED',
  /** 没有可信设备 */
  NO_PEER = 'NO_PEER',
  /** 等待回调超时 */
  TIMEOUT = 'TIMEOUT'
}

/** 同步状态快照，可直接驱动「同步状态可视化面板」 */
export interface SyncSnapshot {
  /** 当前可信对端 */
  peers: PeerDevice[];
  /** 上次同步完成时间戳，0 表示从未同步 */
  lastSyncTime: number;
  /** 上次同步结果 */
  lastOutcome: SyncOutcome;
  /** 累计冲突解决次数 */
  conflictCount: number;
  /** 累计收到远端写入次数 */
  remoteWriteCount: number;
}

/** 数据变更事件 */
export interface ChangeEvent {
  /** 业务键（不含前缀） */
  key: string;
  /** 业务值 */
  value: string;
  /** 是否来自远端设备 */
  fromRemote: boolean;
  /** 变更来源设备的 networkId */
  deviceId: string;
}

/** 变更监听器 */
export type ChangeListener = (event: ChangeEvent) => void;

/** 创建参数 */
export interface DistributedStoreOptions {
  /** 库名，同一应用内唯一，建议按业务命名，如 'favorites' / 'carbon' */
  storeId: string;
  /** 键前缀，用于在同一库内做业务命名空间隔离，默认无前缀 */
  keyPrefix?: string;
  /** 安全等级，默认 S1 */
  securityLevel?: distributedKVStore.SecurityLevel;
}

/** 落库的真实结构：带时间戳与来源设备的信封 */
interface Envelope {
  /** 业务负载 */
  payload: string;
  /** 写入时间戳（毫秒） */
  ts: number;
  /** 写入方 networkId */
  origin: string;
}

// ---------------------------------------------------------------------------
// 实现
// ---------------------------------------------------------------------------

export class DistributedStore {
  private context: common.Context;
  private bundleName: string;
  private storeId: string;
  private keyPrefix: string;
  private kvManager: distributedKVStore.KVManager;
  private kvStore: distributedKVStore.SingleKVStore;
  private dm: distributedDeviceManager.DeviceManager | null;
  private localDeviceId: string;

  /** 本地影子副本：记录每个键「本机已知」的最新信封，用于冲突判定 */
  private shadow: Map<string, Envelope> = new Map<string, Envelope>();
  private listeners: ChangeListener[] = [];

  private conflictCount: number = 0;
  private remoteWriteCount: number = 0;
  private lastSyncTime: number = 0;
  private lastOutcome: SyncOutcome = SyncOutcome.NO_PEER;
  private peers: PeerDevice[] = [];

  /** 变更回调持有固定引用，保证 off() 能正确注销 */
  private changeHandler: (notification: distributedKVStore.ChangeNotification) => void =
    (notification: distributedKVStore.ChangeNotification): void => {
      this.handleChange(notification).catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'handleChange failed: %{public}s', JSON.stringify(e));
      });
    };

  private constructor(
    context: common.Context,
    bundleName: string,
    storeId: string,
    keyPrefix: string,
    kvManager: distributedKVStore.KVManager,
    kvStore: distributedKVStore.SingleKVStore,
    dm: distributedDeviceManager.DeviceManager | null,
    localDeviceId: string
  ) {
    this.context = context;
    this.bundleName = bundleName;
    this.storeId = storeId;
    this.keyPrefix = keyPrefix;
    this.kvManager = kvManager;
    this.kvStore = kvStore;
    this.dm = dm;
    this.localDeviceId = localDeviceId;
  }

  /**
   * 创建并初始化一个分布式存储实例。
   * 内部完成：建库 → 连接设备管理 → 载入影子副本 → 订阅变更。
   */
  static async create(
    context: common.Context,
    options: DistributedStoreOptions
  ): Promise<DistributedStore> {
    const bundleName: string = context.applicationInfo.name;
    const keyPrefix: string = options.keyPrefix === undefined ? '' : options.keyPrefix;
    const securityLevel: distributedKVStore.SecurityLevel =
      options.securityLevel === undefined ? distributedKVStore.SecurityLevel.S1 : options.securityLevel;

    // 1. 分布式 KV 库
    const config: distributedKVStore.KVManagerConfig = {
      context: context,
      bundleName: bundleName
    };
    const kvManager: distributedKVStore.KVManager = distributedKVStore.createKVManager(config);

    const kvOptions: distributedKVStore.Options = {
      createIfMissing: true,
      encrypt: false,
      backup: false,
      autoSync: false,
      kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
      securityLevel: securityLevel
    };
    const kvStore: distributedKVStore.SingleKVStore =
      await DistributedStore.openStore(kvManager, options.storeId, kvOptions);

    // 2. 设备管理（失败不阻断，仅代表无法跨设备同步）
    let dm: distributedDeviceManager.DeviceManager | null = null;
    let localDeviceId: string = '';
    try {
      dm = distributedDeviceManager.createDeviceManager(bundleName);
      localDeviceId = dm.getLocalDeviceNetworkId();
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'createDeviceManager failed: code=%{public}d msg=%{public}s',
        err.code, err.message);
      dm = null;
    }

    // 3. 构造实例
    const instance: DistributedStore = new DistributedStore(
      context, bundleName, options.storeId, keyPrefix, kvManager, kvStore, dm, localDeviceId
    );

    // 4. 载入影子副本（重启后仍能正确判定冲突）
    await instance.loadShadow();

    // 5. 订阅本地与远端变更
    instance.subscribeChange();

    return instance;
  }

  // ------------------------------------------------------------------
  // 读写
  // ------------------------------------------------------------------

  /** 写入字符串。自动盖时间戳并更新影子副本 */
  async put(key: string, value: string): Promise<void> {
    const envelope: Envelope = {
      payload: value,
      ts: Date.now(),
      origin: this.localDeviceId
    };
    this.shadow.set(key, envelope);
    await this.kvPut(this.fullKey(key), JSON.stringify(envelope));
  }

  /** 读取字符串，键不存在时返回 undefined */
  async get(key: string): Promise<string | undefined> {
    const raw: boolean | string | number | Uint8Array | undefined =
      await this.kvGet(this.fullKey(key));
    if (raw === undefined) {
      return undefined;
    }
    return this.unwrap(raw);
  }

  /** 删除键 */
  async delete(key: string): Promise<void> {
    this.shadow.delete(key);
    await this.kvDelete(this.fullKey(key));
  }

  /** 列出全部业务键（已去掉前缀） */
  async keys(): Promise<string[]> {
    const entries: distributedKVStore.Entry[] = await this.kvEntries(this.keyPrefix);
    const out: string[] = [];
    for (let i = 0; i < entries.length; i++) {
      out.push(this.shortKey(entries[i].key));
    }
    return out;
  }

  /** 写入任意可序列化对象 */
  async putObject<T>(key: string, value: T): Promise<void> {
    await this.put(key, JSON.stringify(value));
  }

  /** 读取对象，解析失败或键不存在时返回 undefined */
  async getObject<T>(key: string): Promise<T | undefined> {
    const raw: string | undefined = await this.get(key);
    if (raw === undefined) {
      return undefined;
    }
    try {
      return JSON.parse(raw) as T;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getObject parse failed for key=%{public}s', key);
      return undefined;
    }
  }

  // ------------------------------------------------------------------
  // 设备与同步
  // ------------------------------------------------------------------

  /** 本机 networkId */
  getLocalDeviceId(): string {
    return this.localDeviceId;
  }

  /** 刷新并返回当前可信对端设备列表 */
  refreshPeers(): PeerDevice[] {
    const dm: distributedDeviceManager.DeviceManager | null = this.dm;
    if (dm === null) {
      this.peers = [];
      return this.peers;
    }
    try {
      const list: distributedDeviceManager.DeviceBasicInfo[] = dm.getAvailableDeviceListSync();
      const out: PeerDevice[] = [];
      for (let i = 0; i < list.length; i++) {
        const peer: PeerDevice = {
          deviceId: list[i].deviceId,
          deviceName: list[i].deviceName,
          deviceType: list[i].deviceType
        };
        out.push(peer);
      }
      this.peers = out;
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'getAvailableDeviceListSync failed: code=%{public}d', err.code);
      this.peers = [];
    }
    return this.peers;
  }

  /**
   * 向所有可信设备发起双向同步，并等待 syncComplete 回调。
   * 结果同时写入内部状态，可用 snapshot() 读取。
   */
  async sync(): Promise<SyncOutcome> {
    const peers: PeerDevice[] = this.refreshPeers();
    if (peers.length === 0) {
      this.lastOutcome = SyncOutcome.NO_PEER;
      return this.lastOutcome;
    }

    const deviceIds: string[] = [];
    for (let i = 0; i < peers.length; i++) {
      deviceIds.push(peers[i].deviceId);
    }

    const outcome: SyncOutcome = await this.waitSyncComplete(deviceIds);
    this.lastOutcome = outcome;
    if (outcome !== SyncOutcome.TIMEOUT) {
      this.lastSyncTime = Date.now();
    }
    return outcome;
  }

  /** 注册变更监听 */
  onChange(listener: ChangeListener): void {
    this.listeners.push(listener);
  }

  /** 注销变更监听 */
  offChange(listener: ChangeListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前同步状态快照 */
  snapshot(): SyncSnapshot {
    const snap: SyncSnapshot = {
      peers: this.peers,
      lastSyncTime: this.lastSyncTime,
      lastOutcome: this.lastOutcome,
      conflictCount: this.conflictCount,
      remoteWriteCount: this.remoteWriteCount
    };
    return snap;
  }

  /** 释放资源。调用后本实例不应再使用 */
  close(): void {
    try {
      this.kvStore.off('dataChange', this.changeHandler);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off dataChange failed');
    }
    try {
      this.kvStore.off('syncComplete');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off syncComplete failed');
    }
    const dm: distributedDeviceManager.DeviceManager | null = this.dm;
    if (dm !== null) {
      try {
        distributedDeviceManager.releaseDeviceManager(dm);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'releaseDeviceManager failed');
      }
      this.dm = null;
    }
    this.listeners = [];
    this.shadow.clear();
  }

  // ------------------------------------------------------------------
  // 内部实现
  // ------------------------------------------------------------------

  // ---- 底层 KV 调用集中封装：统一记录日志后抛出 Error，由业务层决定如何处理 ----

  private static async openStore(
    kvManager: distributedKVStore.KVManager,
    storeId: string,
    options: distributedKVStore.Options
  ): Promise<distributedKVStore.SingleKVStore> {
    try {
      return await kvManager.getKVStore<distributedKVStore.SingleKVStore>(storeId, options);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'getKVStore failed storeId=%{public}s code=%{public}d msg=%{public}s',
        storeId, err.code, err.message);
      throw new Error(`getKVStore failed: storeId=${storeId} code=${err.code} msg=${err.message}`);
    }
  }

  private subscribeChange(): void {
    try {
      this.kvStore.on('dataChange', distributedKVStore.SubscribeType.SUBSCRIBE_TYPE_ALL, this.changeHandler);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'subscribe dataChange failed code=%{public}d msg=%{public}s',
        err.code, err.message);
      throw new Error(`subscribe dataChange failed: code=${err.code} msg=${err.message}`);
    }
  }

  private async kvPut(key: string, value: string): Promise<void> {
    try {
      await this.kvStore.put(key, value);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'put failed key=%{public}s code=%{public}d msg=%{public}s',
        key, err.code, err.message);
      throw new Error(`put failed: key=${key} code=${err.code} msg=${err.message}`);
    }
  }

  private async kvGet(key: string): Promise<boolean | string | number | Uint8Array | undefined> {
    try {
      return await this.kvStore.get(key);
    } catch (e) {
      const err = e as BusinessError;
      // 【实测修复】键不存在时分布式 KV 会抛 15100004（Not found），
      // 这不属于异常情况。若不在这里拦掉，get() 就会与它自己的文档
      // （「键不存在时返回 undefined」）矛盾：调用方永远走不到 undefined 分支，
      // 于是「不存在就落一份默认值」这类逻辑全部失效。
      if (err.code === KV_NOT_FOUND) {
        return undefined;
      }
      hilog.error(DOMAIN, TAG, 'get failed key=%{public}s code=%{public}d msg=%{public}s',
        key, err.code, err.message);
      throw new Error(`get failed: key=${key} code=${err.code} msg=${err.message}`);
    }
  }

  private async kvDelete(key: string): Promise<void> {
    try {
      await this.kvStore.delete(key);
    } catch (e) {
      const err = e as BusinessError;
      // 删除不存在的键同样按「已经是目标状态」处理，保证 clearAll() 可重复调用
      if (err.code === KV_NOT_FOUND) {
        return;
      }
      hilog.error(DOMAIN, TAG, 'delete failed key=%{public}s code=%{public}d msg=%{public}s',
        key, err.code, err.message);
      throw new Error(`delete failed: key=${key} code=${err.code} msg=${err.message}`);
    }
  }

  private async kvEntries(prefix: string): Promise<distributedKVStore.Entry[]> {
    try {
      return await this.kvStore.getEntries(prefix);
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'getEntries failed prefix=%{public}s code=%{public}d msg=%{public}s',
        prefix, err.code, err.message);
      throw new Error(`getEntries failed: prefix=${prefix} code=${err.code} msg=${err.message}`);
    }
  }

  private fullKey(key: string): string {
    return this.keyPrefix + key;
  }

  private shortKey(fullKey: string): string {
    if (this.keyPrefix.length > 0 && fullKey.startsWith(this.keyPrefix)) {
      return fullKey.substring(this.keyPrefix.length);
    }
    return fullKey;
  }

  /** 把 Entry.value（接口）转成字符串 */
  private valueToString(value: distributedKVStore.Value): string {
    const raw: Uint8Array | string | number | boolean = value.value;
    if (typeof raw === 'string') {
      return raw as string;
    }
    if (typeof raw === 'number') {
      return `${raw as number}`;
    }
    if (typeof raw === 'boolean') {
      return `${raw as boolean}`;
    }
    return '';
  }

  private parseEnvelope(raw: string): Envelope | undefined {
    if (raw.length === 0) {
      return undefined;
    }
    try {
      const env: Envelope = JSON.parse(raw) as Envelope;
      if (env === null || env === undefined) {
        return undefined;
      }
      return env;
    } catch (e) {
      return undefined;
    }
  }

  private unwrap(raw: boolean | string | number | Uint8Array): string | undefined {
    if (typeof raw !== 'string') {
      return undefined;
    }
    const env: Envelope | undefined = this.parseEnvelope(raw as string);
    return env === undefined ? undefined : env.payload;
  }

  private async loadShadow(): Promise<void> {
    try {
      const entries: distributedKVStore.Entry[] = await this.kvStore.getEntries(this.keyPrefix);
      for (let i = 0; i < entries.length; i++) {
        const env: Envelope | undefined = this.parseEnvelope(this.valueToString(entries[i].value));
        if (env !== undefined) {
          this.shadow.set(this.shortKey(entries[i].key), env);
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.warn(DOMAIN, TAG, 'loadShadow failed: code=%{public}d', err.code);
    }
  }

  /**
   * 处理变更通知。
   * 冲突策略：以最新时间戳的版本为准 —— 若本机影子副本更新，则回写本机版本并计一次冲突。
   */
  private async handleChange(notification: distributedKVStore.ChangeNotification): Promise<void> {
    const sourceDeviceId: string =
      notification.deviceId === undefined ? '' : notification.deviceId;
    const fromRemote: boolean =
      sourceDeviceId.length > 0 && sourceDeviceId !== this.localDeviceId;

    const changed: distributedKVStore.Entry[] = [];
    for (let i = 0; i < notification.insertEntries.length; i++) {
      changed.push(notification.insertEntries[i]);
    }
    for (let i = 0; i < notification.updateEntries.length; i++) {
      changed.push(notification.updateEntries[i]);
    }

    for (let i = 0; i < changed.length; i++) {
      const entry: distributedKVStore.Entry = changed[i];
      const incoming: Envelope | undefined = this.parseEnvelope(this.valueToString(entry.value));
      if (incoming === undefined) {
        continue;
      }

      const key: string = this.shortKey(entry.key);
      const local: Envelope | undefined = this.shadow.get(key);

      // 本机版本更新 → 冲突，以本机为准并回写，避免被较旧数据覆盖
      if (local !== undefined && local.ts > incoming.ts) {
        this.conflictCount++;
        hilog.info(DOMAIN, TAG,
          'conflict on key=%{public}s: local ts=%{public}d wins over remote ts=%{public}d',
          key, local.ts, incoming.ts);
        await this.kvPut(entry.key, JSON.stringify(local));
        continue;
      }

      this.shadow.set(key, incoming);
      if (fromRemote) {
        this.remoteWriteCount++;
      }

      const event: ChangeEvent = {
        key: key,
        value: incoming.payload,
        fromRemote: fromRemote,
        deviceId: sourceDeviceId
      };
      this.emit(event);
    }
  }

  private emit(event: ChangeEvent): void {
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](event);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'listener threw on key=%{public}s', event.key);
      }
    }
  }

  private waitSyncComplete(deviceIds: string[]): Promise<SyncOutcome> {
    return new Promise<SyncOutcome>((resolve: (value: SyncOutcome) => void) => {
      let settled: boolean = false;

      const finish = (outcome: SyncOutcome): void => {
        if (settled) {
          return;
        }
        settled = true;
        try {
          this.kvStore.off('syncComplete');
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'off syncComplete failed');
        }
        resolve(outcome);
      };

      const timer: number = setTimeout(() => {
        finish(SyncOutcome.TIMEOUT);
      }, SYNC_TIMEOUT_MS);

      this.kvStore.on('syncComplete', (result: Array<[string, number]>) => {
        clearTimeout(timer);
        let ok: number = 0;
        let bad: number = 0;
        for (let i = 0; i < result.length; i++) {
          if (result[i][1] === 0) {
            ok++;
          } else {
            bad++;
          }
        }
        if (bad === 0) {
          finish(SyncOutcome.SUCCESS);
        } else if (ok > 0) {
          finish(SyncOutcome.PARTIAL);
        } else {
          finish(SyncOutcome.FAILED);
        }
      });

      try {
        this.kvStore.sync(deviceIds, distributedKVStore.SyncMode.PUSH_PULL);
      } catch (e) {
        clearTimeout(timer);
        const err = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'sync failed: code=%{public}d msg=%{public}s', err.code, err.message);
        finish(SyncOutcome.FAILED);
      }
    });
  }
}
