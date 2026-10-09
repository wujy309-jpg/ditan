/**
 * 模拟城市碳普惠平台接口 —— 创新拓展 3
 *
 * 赛题原文：「平台对接：模拟城市碳普惠接口，实现积分互通与权益兑换。」
 *
 * 为什么用 mock 而不是真接口：
 *   1. 城市碳普惠平台没有对个人开发者开放的公开 API；
 *   2. 路演现场必须离线可用，不能依赖网络。
 *
 * 但 mock 保留了真实接口的**全部语义**——异步、网络延迟、业务错误码、库存、
 * 幂等、账户状态——因此演示时与真接口的表现一致，答辩时也站得住：
 * 「换真接口只需替换 transport 层，业务层不用动」。这一点在代码里刻意体现为
 * `CarbonInclusiveApi` 只依赖 `store`，不依赖任何 UI。
 *
 * 数据落在同一个分布式 KV 库里，键前缀 `platform:`，因此家庭多设备合并时
 * 平台侧账户也会跟着同步。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DistributedStore } from '../common/DistributedStore';

const DOMAIN: number = 0x0004;
const TAG: string = 'CarbonXPlat';

/** 平台侧键前缀 */
const P_PREFIX: string = 'platform:';
const K_ACCOUNT: string = P_PREFIX + 'account';
const K_ORDER: string = P_PREFIX + 'order:';
const K_STOCK: string = P_PREFIX + 'stock:';

/** 业务返回码（模拟真实平台的错误码体系） */
export enum ApiCode {
  OK = 0,
  /** 未绑定平台账户 */
  NOT_BOUND = 1001,
  /** 积分不足 */
  INSUFFICIENT = 1002,
  /** 权益已兑完 */
  OUT_OF_STOCK = 1003,
  /** 模拟的网络异常 */
  NETWORK = 9001
}

/** 可兑换权益 */
export interface Benefit {
  id: string;
  name: string;
  /** 提供方，模拟真实碳普惠平台的合作商户 */
  provider: string;
  /** 所需平台积分 */
  cost: number;
  /** 初始库存 */
  stock: number;
  desc: string;
}

/** 平台账户 */
export interface PlatformAccount {
  bound: boolean;
  /** 平台侧账户号 */
  accountId: string;
  /** 平台积分（与本地碳积分 1:1 互通） */
  points: number;
  /** 最近一次上报积分的时间 */
  lastReportTs: number;
  /** 累计已上报的平台积分，用于算出还有多少本地积分未上报 */
  reportedTotal: number;
  /** 累计已兑换次数 */
  exchangedCount: number;
}

/** 统一返回结构 */
export interface ApiResult {
  code: number;
  message: string;
  /** 兑换成功时返回订单号 */
  orderId: string;
}

/** 兑换订单 */
export interface ExchangeOrder {
  orderId: string;
  benefitId: string;
  benefitName: string;
  cost: number;
  ts: number;
}

/**
 * 平台内置权益目录。
 * 定价刻意做成「小额度可快速兑到、大额度需要持续记录」，
 * 这样 5 分钟演示里既能展示兑换成功，也能展示积分不足的分支。
 */
const BENEFITS: Benefit[] = [
  {
    id: 'b.metro',
    name: '地铁乘车券（单程）',
    provider: '郑州地铁 · 碳普惠专区',
    cost: 120,
    stock: 50,
    desc: '兑换后凭券码乘坐地铁一次'
  },
  {
    id: 'b.bike',
    name: '共享单车 30 分钟免费券',
    provider: '城市出行 · 碳普惠专区',
    cost: 60,
    stock: 80,
    desc: '低碳出行叠加优惠'
  },
  {
    id: 'b.bag',
    name: '环保购物袋',
    provider: '社区服务站',
    cost: 200,
    stock: 30,
    desc: '线下社区服务点自提'
  },
  {
    id: 'b.ticket',
    name: '城市公园门票',
    provider: '市园林局 · 碳普惠专区',
    cost: 500,
    stock: 20,
    desc: '指定公园通用'
  },
  {
    id: 'b.power',
    name: '电费红包 5 元',
    provider: '国网 · 碳普惠专区',
    cost: 800,
    stock: 10,
    desc: '充值至绑定户号'
  }
];

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(resolve, ms);
  });
}

/** 生成订单号：日期 + 随机串，模拟平台侧单号 */
function makeOrderId(): string {
  const rand: number = Math.floor(Math.random() * 1000000);
  return `CP${Date.now()}${rand}`;
}

export class CarbonInclusiveApi {
  private store: DistributedStore;

  constructor(store: DistributedStore) {
    this.store = store;
  }

  // ------------------------------------------------------------------
  // 账户
  // ------------------------------------------------------------------

  /** 读取平台账户；未绑定时返回 bound=false 的空账户 */
  async getAccount(): Promise<PlatformAccount> {
    const acc: PlatformAccount | undefined =
      await this.store.getObject<PlatformAccount>(K_ACCOUNT);
    if (acc === undefined) {
      const empty: PlatformAccount = {
        bound: false,
        accountId: '',
        points: 0,
        lastReportTs: 0,
        reportedTotal: 0,
        exchangedCount: 0
      };
      return empty;
    }
    return acc;
  }

  /**
   * 绑定平台账户（幂等）。
   * 真实平台这里是 OAuth 授权 + 手机号绑定，mock 用本机 networkId 派生账户号。
   */
  async bindAccount(localDeviceId: string): Promise<ApiResult> {
    await delay(300);
    const existing: PlatformAccount = await this.getAccount();
    if (existing.bound) {
      const r: ApiResult = { code: ApiCode.OK, message: '账户已绑定', orderId: '' };
      return r;
    }
    const seed: string = localDeviceId.length > 0 ? localDeviceId : `${Date.now()}`;
    const suffix: string = seed.substring(Math.max(0, seed.length - 8));
    const acc: PlatformAccount = {
      bound: true,
      accountId: `CP-${suffix.toUpperCase()}`,
      points: 0,
      lastReportTs: 0,
      reportedTotal: 0,
      exchangedCount: 0
    };
    await this.store.putObject<PlatformAccount>(K_ACCOUNT, acc);
    hilog.info(DOMAIN, TAG, 'account bound: %{public}s', acc.accountId);
    const r: ApiResult = { code: ApiCode.OK, message: '绑定成功', orderId: '' };
    return r;
  }

  // ------------------------------------------------------------------
  // 积分互通
  // ------------------------------------------------------------------

  /**
   * 把本地碳积分上报到平台（积分互通）。
   * 幂等设计：上报的是「增量」，由调用方保证只上报一次未上报的部分。
   */
  async reportPoints(points: number): Promise<ApiResult> {
    await delay(400);
    const acc: PlatformAccount = await this.getAccount();
    if (!acc.bound) {
      const r: ApiResult = { code: ApiCode.NOT_BOUND, message: '请先绑定碳普惠账户', orderId: '' };
      return r;
    }
    if (points <= 0) {
      const r: ApiResult = { code: ApiCode.OK, message: '没有需要上报的积分', orderId: '' };
      return r;
    }
    acc.points += points;
    acc.reportedTotal += points;
    acc.lastReportTs = Date.now();
    await this.store.putObject<PlatformAccount>(K_ACCOUNT, acc);
    hilog.info(DOMAIN, TAG, 'reported %{public}d points, total=%{public}d', points, acc.points);
    const r: ApiResult = { code: ApiCode.OK, message: `已上报 ${points} 平台积分`, orderId: '' };
    return r;
  }

  // ------------------------------------------------------------------
  // 权益
  // ------------------------------------------------------------------

  /** 查询权益列表（含剩余库存） */
  async listBenefits(): Promise<Benefit[]> {
    await delay(250);
    const out: Benefit[] = [];
    for (let i = 0; i < BENEFITS.length; i++) {
      const b: Benefit = BENEFITS[i];
      const used: number | undefined =
        await this.store.getObject<number>(K_STOCK + b.id);
      const remaining: number = b.stock - (used === undefined ? 0 : used);
      const item: Benefit = {
        id: b.id,
        name: b.name,
        provider: b.provider,
        cost: b.cost,
        stock: remaining < 0 ? 0 : remaining,
        desc: b.desc
      };
      out.push(item);
    }
    return out;
  }

  /**
   * 兑换权益。
   * 完整走一遍真实平台的校验顺序：账户 → 库存 → 积分 → 扣减 → 出单。
   */
  async exchange(benefitId: string): Promise<ApiResult> {
    await delay(600);

    const acc: PlatformAccount = await this.getAccount();
    if (!acc.bound) {
      const r: ApiResult = { code: ApiCode.NOT_BOUND, message: '请先绑定碳普惠账户', orderId: '' };
      return r;
    }

    let target: Benefit | undefined = undefined;
    for (let i = 0; i < BENEFITS.length; i++) {
      if (BENEFITS[i].id === benefitId) {
        target = BENEFITS[i];
        break;
      }
    }
    if (target === undefined) {
      const r: ApiResult = { code: ApiCode.NETWORK, message: '权益不存在', orderId: '' };
      return r;
    }

    const used: number | undefined = await this.store.getObject<number>(K_STOCK + target.id);
    const usedCount: number = used === undefined ? 0 : used;
    if (usedCount >= target.stock) {
      const r: ApiResult = { code: ApiCode.OUT_OF_STOCK, message: '该权益已兑完', orderId: '' };
      return r;
    }

    if (acc.points < target.cost) {
      const r: ApiResult = {
        code: ApiCode.INSUFFICIENT,
        message: `平台积分不足，还差 ${target.cost - acc.points} 分`,
        orderId: ''
      };
      return r;
    }

    // 扣积分、扣库存、出单
    acc.points -= target.cost;
    acc.exchangedCount += 1;
    await this.store.putObject<PlatformAccount>(K_ACCOUNT, acc);
    await this.store.putObject<number>(K_STOCK + target.id, usedCount + 1);

    const order: ExchangeOrder = {
      orderId: makeOrderId(),
      benefitId: target.id,
      benefitName: target.name,
      cost: target.cost,
      ts: Date.now()
    };
    await this.store.putObject<ExchangeOrder>(K_ORDER + order.orderId, order);

    hilog.info(DOMAIN, TAG, 'exchanged %{public}s order=%{public}s',
      target.name, order.orderId);
    const r: ApiResult = {
      code: ApiCode.OK,
      message: `兑换成功：${target.name}`,
      orderId: order.orderId
    };
    return r;
  }

  /** 查询兑换记录，按时间倒序 */
  async listOrders(): Promise<ExchangeOrder[]> {
    const keys: string[] = await this.store.keys();
    const out: ExchangeOrder[] = [];
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].startsWith(K_ORDER)) {
        const o: ExchangeOrder | undefined =
          await this.store.getObject<ExchangeOrder>(keys[i]);
        if (o !== undefined) {
          out.push(o);
        }
      }
    }
    out.sort((a: ExchangeOrder, b: ExchangeOrder): number => b.ts - a.ts);
    return out;
  }
}
