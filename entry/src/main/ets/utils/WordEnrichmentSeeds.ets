/** Curated lexical notes, not exam-frequency statistics. Unlisted words retain the offline dictionary. */
export class EnrichmentSeed {
  word: string;
  coreMeanings: string[];
  collocations: string[];
  root: string;
  prefix: string;
  suffix: string;
  analysis: string;
  family: string[];

  constructor(word: string, coreMeanings: string[], collocations: string[], root: string = '',
    prefix: string = '', suffix: string = '', analysis: string = '', family: string[] = []) {
    this.word = word;
    this.coreMeanings = coreMeanings;
    this.collocations = collocations;
    this.root = root;
    this.prefix = prefix;
    this.suffix = suffix;
    this.analysis = analysis;
    this.family = family;
  }
}

export class ConfusingSeed {
  first: string;
  second: string;
  note: string;
  constructor(first: string, second: string, note: string) {
    this.first = first;
    this.second = second;
    this.note = note;
  }
}

export const ENRICHMENT_SEEDS: EnrichmentSeed[] = [
  new EnrichmentSeed('abandon', ['v. 放弃；抛弃'], ['abandon an attempt 放弃尝试', 'abandon hope 放弃希望']),
  new EnrichmentSeed('address', ['v. 处理；解决', 'n. 地址；演说'], ['address a problem 处理问题', 'deliver an address 发表演说']),
  new EnrichmentSeed('novel', ['adj. 新颖的', 'n. 小说'], ['a novel approach 新方法', 'a historical novel 历史小说']),
  new EnrichmentSeed('adapt', ['v. 适应；改编'], ['adapt to change 适应变化', 'adapt a novel for film 将小说改编成电影'], 'adapt', '', '', 'adaptation 是 adapt 的名词派生形式。', ['adapt', 'adaptation', 'adaptable']),
  new EnrichmentSeed('adopt', ['v. 采用；收养'], ['adopt a policy 采用政策', 'adopt a child 收养孩子'], 'adopt', '', '', 'adoption 是 adopt 的名词派生形式。', ['adopt', 'adoption']),
  new EnrichmentSeed('adept', ['adj. 熟练的'], ['be adept at 熟练于']),
  new EnrichmentSeed('complement', ['v. 补充；使完善', 'n. 补充物'], ['complement each other 相互补充']),
  new EnrichmentSeed('compliment', ['n. 赞美；恭维', 'v. 赞美'], ['pay someone a compliment 称赞某人', 'compliment someone on something 因某事称赞某人']),
  new EnrichmentSeed('stationary', ['adj. 静止的；不动的'], ['remain stationary 保持静止']),
  new EnrichmentSeed('stationery', ['n. 文具'], ['office stationery 办公文具']),
  new EnrichmentSeed('affect', ['v. 影响'], ['affect the outcome 影响结果']),
  new EnrichmentSeed('effect', ['n. 影响；效果', 'v. 使发生'], ['have an effect on 对……有影响', 'effect a change 促成变化']),
  new EnrichmentSeed('economic', ['adj. 经济的'], ['economic growth 经济增长']),
  new EnrichmentSeed('economical', ['adj. 节约的；经济实惠的'], ['an economical car 节油的汽车']),
  new EnrichmentSeed('principal', ['adj. 主要的', 'n. 校长；本金'], ['the principal reason 主要原因']),
  new EnrichmentSeed('principle', ['n. 原则；原理'], ['in principle 原则上', 'a basic principle 基本原理']),
  new EnrichmentSeed('distract', ['v. 使分心'], ['distract someone from 使某人分心'], 'tract', 'dis-', '', 'dis-（分开）+ tract（拉）：把注意力拉开，因而使分心。', ['distract', 'attract', 'extract', 'retract', 'contract']),
  new EnrichmentSeed('attract', ['v. 吸引'], ['attract attention 吸引注意'], 'tract', 'at-', '', 'at- 是 ad- 的变体（朝向），tract 表示拉：拉向自己，因而吸引。', ['distract', 'attract', 'extract', 'retract', 'contract']),
  new EnrichmentSeed('extract', ['v. 提取；拔出', 'n. 摘录'], ['extract information 提取信息'], 'tract', 'ex-', '', 'ex-（向外）+ tract（拉）：向外拉出，因而提取。', ['distract', 'attract', 'extract', 'retract', 'contract']),
  new EnrichmentSeed('retract', ['v. 撤回；缩回'], ['retract a statement 撤回声明'], 'tract', 're-', '', 're-（向后）+ tract（拉）：拉回，因而撤回。', ['distract', 'attract', 'extract', 'retract', 'contract']),
  new EnrichmentSeed('contract', ['n. 合同', 'v. 收缩；订约'], ['sign a contract 签订合同', 'contract a disease 染病'], 'tract', 'con-', '', 'con-（一起）+ tract（拉）：拉到一起，产生收缩、约定等含义。', ['distract', 'attract', 'extract', 'retract', 'contract']),
  new EnrichmentSeed('inspect', ['v. 检查；视察'], ['inspect the equipment 检查设备'], 'spect', 'in-', '', 'in-（向内）+ spect（看）：仔细查看，因而检查。', ['inspect', 'respect', 'prospect', 'spectator']),
  new EnrichmentSeed('respect', ['v. 尊重', 'n. 尊重；方面'], ['show respect for 尊重', 'in this respect 在这方面'], 'spect', 're-', '', 're-（回）+ spect（看）：回看、顾及，发展为尊重。', ['inspect', 'respect', 'prospect', 'spectator']),
  new EnrichmentSeed('transport', ['v. 运输', 'n. 交通运输'], ['public transport 公共交通'], 'port', 'trans-', '', 'trans-（跨越）+ port（携带）：从一处带到另一处，因而运输。', ['transport', 'export', 'import', 'portable']),
  new EnrichmentSeed('export', ['v. 出口', 'n. 出口商品'], ['export goods 出口商品'], 'port', 'ex-', '', 'ex-（向外）+ port（携带）：向外运送，因而出口。', ['transport', 'export', 'import', 'portable']),
  new EnrichmentSeed('import', ['v. 进口', 'n. 进口商品'], ['import goods 进口商品'], 'port', 'im-', '', 'im- 是 in- 的变体（向内），port 表示携带：向内运送，因而进口。', ['transport', 'export', 'import', 'portable']),
  new EnrichmentSeed('portable', ['adj. 便携的'], ['a portable device 便携设备'], 'port', '', '-able', 'port（携带）+ -able（可以……的）：可以携带的。', ['transport', 'export', 'import', 'portable']),
  new EnrichmentSeed('predict', ['v. 预测'], ['predict the outcome 预测结果'], 'dict', 'pre-', '', 'pre-（在前）+ dict（说）：事先说出，因而预测。', ['predict', 'contradict', 'dictate', 'prediction']),
  new EnrichmentSeed('contradict', ['v. 反驳；与……矛盾'], ['contradict a statement 反驳声明'], 'dict', 'contra-', '', 'contra-（反对）+ dict（说）：说出相反的意见，因而反驳。', ['predict', 'contradict', 'dictate', 'prediction']),
  new EnrichmentSeed('comply', ['v. 遵守；服从'], ['comply with regulations 遵守规定']),
  new EnrichmentSeed('susceptible', ['adj. 易受影响的；易患病的'], ['be susceptible to 易受……影响']),
  new EnrichmentSeed('rely', ['v. 依赖；信赖'], ['rely on 依赖；信赖', 'rely heavily on 严重依赖']),
  new EnrichmentSeed('maintain', ['v. 维持；保养；坚持认为'], ['maintain a balance 保持平衡', 'maintain that 坚持认为']),
  new EnrichmentSeed('retain', ['v. 保留；保持'], ['retain information 记住信息', 'retain control 保持控制']),
  new EnrichmentSeed('resilient', ['adj. 有韧性的；能迅速恢复的'], ['remain resilient 保持韧性'])
];

export const CONFUSING_SEEDS: ConfusingSeed[] = [
  new ConfusingSeed('adapt', 'adopt', 'adapt to 是适应；adopt a policy 是采用。adapt a novel 是改编小说，adopt a child 是收养孩子。'),
  new ConfusingSeed('adapt', 'adept', 'adapt 是动词“适应”；adept 是形容词“熟练的”，常用 be adept at。'),
  new ConfusingSeed('adopt', 'adept', 'adopt 是“采用、收养”；adept 是“熟练的”，注意元音字母 o 与 e。'),
  new ConfusingSeed('complement', 'compliment', 'complement 表示补充、完善，如 complement each other；compliment 表示赞美，如 pay a compliment。'),
  new ConfusingSeed('stationary', 'stationery', 'stationary 的 a 对应“不动的”；stationery 的 e 对应“文具”，如 office stationery。'),
  new ConfusingSeed('affect', 'effect', 'affect 常作动词“影响”；effect 常作名词“效果、影响”。effect 作动词时表示“使发生”，如 effect a change。'),
  new ConfusingSeed('economic', 'economical', 'economic 指与经济有关，如 economic growth；economical 指节约、实惠，如 an economical car。'),
  new ConfusingSeed('principal', 'principle', 'principal 可指“主要的、校长、本金”；principle 仅为名词，表示“原则、原理”。')
];
