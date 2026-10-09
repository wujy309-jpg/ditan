/**
 * 桌面卡片数据服务 —— 创新拓展（鸿蒙特色能力）
 *
 * 作用：让用户在**桌面上直接看到今日碳数据**，不必打开应用。
 * 这是鸿蒙「万能卡片」能力，安卓与小程序无法实现同等体验。
 *
 * 数据从哪来：
 *   FormExtensionAbility 与主应用属于同一个应用，因此可以直接读取同一套
 *   分布式 KV 库（storeId='carbon'）。卡片本身只负责渲染，
 *   所有数据在这里读好后通过 formBindingData 传给卡片。
 *
 * 为什么不在卡片 UI 里直接读数据：
 *   卡片渲染在独立进程中，只适合渲染纯数据。把读取逻辑收在 Ability 里，
 *   卡片侧只接收字符串，既轻量又不容易踩到卡片组件的限制。
 *
 * 更新时机：
 *   1. 卡片被添加到桌面时（onAddForm）
 *   2. 系统按 form_config 的 updateDuration 定期拉取（onUpdateForm）
 *   3. 用户在应用里新增记录后，主应用主动调用本模块的 refreshAllCards()
 */
import { common } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Want } from '@kit.AbilityKit';
import { DistributedStore, DistributedStoreOptions } from '../common/DistributedStore';
import { BehaviorRecord, categoryLabel, round2 } from '../model/Models';

const DOMAIN: number = 0x0007;
const TAG: string = 'CarbonCard';

/** 与主应用保持一致的库名与前缀 */
const STORE_ID: string = 'carbon';
const KEY_PREFIX: string = 'carbon:';
/** 卡片 ID 存在 preferences 里：它是设备本地信息，不该参与跨设备同步 */
const PREF_NAME: string = 'carbon_card_store';
const PREF_KEY_IDS: string = 'form_ids';

/** 传给卡片的键 */
export interface CardData {
  /** 今日减排量，已格式化 */
  todaySaved: string;
  /** 今日获得的积分 */
  todayPoints: string;
  /** 累计减排量 */
  totalSaved: string;
  /** 记录条数 */
  recordCount: string;
  /** 今日已记录的类目数 */
  todayKinds: string;
  /** 当日日期，如 9月30日 */
  dateText: string;
  /** 近 7 日柱状高度（0~100 的百分数，逗号分隔） */
  bars: string;
  /** 近 7 日日期标签（逗号分隔） */
  weekLabels: string;
  /** 一句话激励语 */
  tip: string;
}

/** 把 Date 变成「9月30日」 */
function dateText(d: Date): string {
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}

/** 把 Date 变成 YYYY-MM-DD */
function isoDate(d: Date): string {
  const m: number = d.getMonth() + 1;
  const day: number = d.getDate();
  const mm: string = m < 10 ? `0${m}` : `${m}`;
  const dd: string = day < 10 ? `0${day}` : `${day}`;
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/**
 * 读取今日与近 7 日数据，组装成卡片要渲染的纯字符串对象。
 * 任何一步失败都返回一份「空白但可用」的数据，保证卡片不白屏。
 */
async function loadCardData(ctx: common.Context): Promise<CardData> {
  const empty: CardData = {
    todaySaved: '0',
    todayPoints: '0',
    totalSaved: '0',
    recordCount: '0',
    todayKinds: '0',
    dateText: dateText(new Date()),
    bars: '0,0,0,0,0,0,0',
    weekLabels: '',
    tip: '打开应用记录第一笔低碳行为'
  };

  try {
    const options: DistributedStoreOptions = { storeId: STORE_ID, keyPrefix: KEY_PREFIX };
    const store: DistributedStore = await DistributedStore.create(ctx, options);

    const keys: string[] = await store.keys();
    const today: string = isoDate(new Date());

    let total: number = 0;
    let todaySaved: number = 0;
    let recordCount: number = 0;
    let todayPoints: number = 0;
    const todayCats: string[] = [];

    // 近 7 日分桶（下标 0 = 6 天前，6 = 今天）
    const buckets: number[] = [0, 0, 0, 0, 0, 0, 0];
    const labels: string[] = [];
    for (let i = 0; i < 7; i++) {
      const d: Date = new Date();
      d.setDate(d.getDate() - (6 - i));
      labels.push(`${d.getMonth() + 1}/${d.getDate()}`);
    }
    const dayKeys: string[] = [];
    for (let i = 0; i < 7; i++) {
      const d: Date = new Date();
      d.setDate(d.getDate() - (6 - i));
      dayKeys.push(isoDate(d));
    }

    for (let i = 0; i < keys.length; i++) {
      if (!keys[i].startsWith('behavior:')) {
        continue;
      }
      const rec: BehaviorRecord | undefined =
        await store.getObject<BehaviorRecord>(keys[i]);
      if (rec === undefined) {
        continue;
      }
      total += rec.saved;
      recordCount++;
      if (rec.date === today) {
        todaySaved += rec.saved;
        if (todayCats.indexOf(rec.category) < 0) {
          todayCats.push(rec.category);
        }
      }
      const bi: number = dayKeys.indexOf(rec.date);
      if (bi >= 0) {
        buckets[bi] += rec.saved;
      }
    }

    // 今日积分 = 今日新增记录的积分（与主应用规则一致：每 kg 得 100 分）
    todayPoints = Math.max(0, Math.round(todaySaved * 100));

    // 柱状高度归一化到 0~100，最低给 6 以免完全看不见
    let maxV: number = 0;
    for (let i = 0; i < buckets.length; i++) {
      if (buckets[i] > maxV) {
        maxV = buckets[i];
      }
    }
    const bars: string[] = [];
    for (let i = 0; i < buckets.length; i++) {
      if (maxV <= 0) {
        bars.push('6');
      } else {
        const h: number = Math.round(buckets[i] / maxV * 100);
        bars.push(`${h < 6 ? 6 : h}`);
      }
    }

    let tip: string = '今天还没有记录，记一笔吧';
    const kinds: number = todayCats.length;
    if (kinds >= 3) {
      tip = `已覆盖 ${kinds} 类低碳行为，很全面`;
    } else if (kinds === 2) {
      tip = '已记录 2 类，再补一类更完整';
    } else if (kinds === 1) {
      tip = `已记录「${categoryLabel(todayCats[0])}」，继续加油`;
    }

    const data: CardData = {
      todaySaved: `${round2(todaySaved)}`,
      todayPoints: `${todayPoints}`,
      totalSaved: `${round2(total)}`,
      recordCount: `${recordCount}`,
      todayKinds: `${kinds}`,
      dateText: dateText(new Date()),
      bars: bars.join(','),
      weekLabels: labels.join(','),
      tip: tip
    };
    return data;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'loadCardData failed: %{public}s', JSON.stringify(e));
    return empty;
  }
}

/** 从 preferences 读已添加的卡片 ID */
async function readFormIds(ctx: common.Context): Promise<string[]> {
  try {
    const store = await preferences.getPreferences(ctx, PREF_NAME);
    const raw = await store.get(PREF_KEY_IDS, '[]');
    const arr: string[] = JSON.parse(raw as string) as string[];
    return arr;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'readFormIds failed');
    return [];
  }
}

async function writeFormIds(ctx: common.Context, ids: string[]): Promise<void> {
  try {
    const store = await preferences.getPreferences(ctx, PREF_NAME);
    await store.put(PREF_KEY_IDS, JSON.stringify(ids));
    await store.flush();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'writeFormIds failed');
  }
}

/**
 * 主动刷新所有已添加的卡片。
 * 由主应用在「新增一条记录」之后调用，让桌面卡片立刻反映最新数据。
 */
export async function refreshAllCards(ctx: common.Context): Promise<void> {
  const ids: string[] = await readFormIds(ctx);
  if (ids.length === 0) {
    return;
  }
  const data: CardData = await loadCardData(ctx);
  const binding: formBindingData.FormBindingData =
    formBindingData.createFormBindingData(data);
  for (let i = 0; i < ids.length; i++) {
    try {
      await formProvider.updateForm(ids[i], binding);
      hilog.info(DOMAIN, TAG, 'card updated: %{public}s', ids[i]);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'updateForm failed for %{public}s', ids[i]);
    }
  }
}

/**
 * 卡片扩展 Ability。
 * 生命周期回调都是同步签名，因此内部用异步任务读取数据并回调 updateForm。
 */
export default class CarbonCardAbility extends FormExtensionAbility {
  /** 卡片被添加到桌面 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    const ctx = this.context;
    const formId: string = want.parameters === undefined
      ? '' : (want.parameters[formInfo.FormParam.IDENTITY_KEY] as string);

    hilog.info(DOMAIN, TAG, 'onAddForm formId=%{public}s', formId);

    // 记录卡片 ID，并异步推送首帧数据
    (async () => {
      if (formId.length > 0) {
        const ids: string[] = await readFormIds(ctx);
        if (ids.indexOf(formId) < 0) {
          ids.push(formId);
          await writeFormIds(ctx, ids);
        }
      }
      try {
        const data: CardData = await loadCardData(ctx);
        await formProvider.updateForm(formId,
          formBindingData.createFormBindingData(data));
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'push first frame failed');
      }
    })();

    // 返回一份占位数据，保证卡片立刻有内容可渲染
    const placeholder: CardData = {
      todaySaved: '—',
      todayPoints: '—',
      totalSaved: '—',
      recordCount: '—',
      todayKinds: '0',
      dateText: dateText(new Date()),
      bars: '6,6,6,6,6,6,6',
      weekLabels: '',
      tip: '正在加载今日碳数据…'
    };
    return formBindingData.createFormBindingData(placeholder);
  }

  /** 系统定期或在应用主动请求时刷新 */
  onUpdateForm(formId: string): void {
    const ctx = this.context;
    (async () => {
      try {
        const data: CardData = await loadCardData(ctx);
        await formProvider.updateForm(formId,
          formBindingData.createFormBindingData(data));
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'onUpdateForm failed');
      }
    })();
  }

  /** 卡片被移除 */
  onRemoveForm(formId: string): void {
    const ctx = this.context;
    (async () => {
      const ids: string[] = await readFormIds(ctx);
      const left: string[] = [];
      for (let i = 0; i < ids.length; i++) {
        if (ids[i] !== formId) {
          left.push(ids[i]);
        }
      }
      await writeFormIds(ctx, left);
      hilog.info(DOMAIN, TAG, 'onRemoveForm formId=%{public}s', formId);
    })();
  }
}
