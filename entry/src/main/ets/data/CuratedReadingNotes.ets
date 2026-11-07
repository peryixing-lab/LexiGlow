import { ReadingWordNote } from '../model/ArticleModels';

/** Explicit story context, never inferred from capitalisation or used to replace dictionary definitions. */
export function curatedReadingPersonNames(id: number): string[] {
  switch (id) {
    case -1: return ['Mia'];
    case -2: return ['Daniel'];
    case -3: return ['Lena'];
    case -4: return ['Omar'];
    case -5: return ['Ben'];
    case -6: return ['Eva', 'Sam'];
    case -7: return ['Nora'];
    case -8: return ['Leo'];
    case -9: return ['Alice'];
    case -10: return ['Rui', 'Mina', 'Tom'];
    case -11: return ['Jin', 'Elena'];
    case -12: return ['Sara', 'Mei'];
    case -13: return ['Amir'];
    case -14: return ['Grace'];
    case -16: return ['Theo'];
    case -17: return ['Lin'];
    case -18: return ['Maya'];
    default: return [];
  }
}

function readingWordNote(headword: string, example: string, translation: string, collocation: string): ReadingWordNote {
  const note = new ReadingWordNote(); note.headword = headword; note.example = example;
  note.translation = translation; note.collocation = collocation; return note;
}

/** Authored notes quote the exact story. They supplement reading without replacing user dictionary content. */
export function curatedReadingNotes(id: number): ReadingWordNote[] {
  switch (id) {
    case -1: return [
      readingWordNote("umbrella", "She offered to share her umbrella.", "她提出和他共用一把伞。", "share an umbrella · 共用一把伞"),
      readingWordNote("share", "She offered to share her umbrella.", "她提出和他共用一把伞。", "share something with someone · 与某人分享某物"),
      readingWordNote("kindness", "A small act of kindness had made an ordinary afternoon feel warmer.", "一个小小的善举让平常的午后多了暖意。", "an act of kindness · 一个善举")
    ];
    case -2: return [
      readingWordNote("routine", "One Sunday, he decided to try a different routine.", "一个周日，他决定尝试一种不同的日常安排。", "a daily routine · 日常安排"),
      readingWordNote("habit", "He kept the habit because it was simple enough to repeat.", "他保留了这个习惯，因为它足够简单，便于坚持。", "keep a habit · 保持一个习惯"),
      readingWordNote("choose", "However, those quiet minutes gave him a little space to choose how to begin.", "不过，那几分钟的安静让他能从容选择如何开始一天。", "choose how to begin · 选择如何开始")
    ];
    case -3: return [
      readingWordNote("seed", "She nearly bought a new packet of seeds.", "她差一点就买了一包新的种子。", "a packet of seeds · 一包种子"),
      readingWordNote("growth", "Her neighbor reminded her that growth often begins where we cannot see it.", "邻居提醒她，生长往往从看不见的地方开始。", "notice growth · 留意生长变化"),
      readingWordNote("notice", "Over the following weeks, she learned to notice small changes instead of expecting a harvest immediately.", "接下来的几周，她学会了留意微小变化，而不是期待立即收获。", "notice small changes · 留意细微变化")
    ];
    case -4: return [
      readingWordNote("repair", "The repair took less than an hour.", "这次修理花了不到一小时。", "a simple repair · 一次简单修理"),
      readingWordNote("volunteer", "A volunteer examined the lamp and found a damaged wire.", "一位志愿者检查台灯，发现了一根损坏的电线。", "work as a volunteer · 做志愿者"),
      readingWordNote("donation", "Omar paid for the wire and left a small donation for the shop.", "Omar 支付了电线费用，还给店里留了一点捐款。", "make a donation · 捐款")
    ];
    case -5: return [
      readingWordNote("receipt", "When he got home, he checked the receipt.", "回家后，他核对了购物小票。", "check the receipt · 核对小票"),
      readingWordNote("basket", "At the shop, he put everything in his basket and paid at the counter.", "在店里，他把东西都放进购物篮，然后到柜台付款。", "a shopping basket · 购物篮"),
      readingWordNote("refund", "The woman at the counter checked them and gave him a refund for the extra bottle.", "柜台的女士核对后，退还了多收一瓶牛奶的钱。", "give someone a refund · 给某人退款")
    ];
    case -6: return [
      readingWordNote("borrow", "Eva borrowed a book from the school library on Monday.", "周一，Eva 从学校图书馆借了一本书。", "borrow a book from the library · 从图书馆借书"),
      readingWordNote("return", "Eva returned the book, and Sam borrowed it with his own card.", "Eva 归还图书后，Sam 用自己的借书卡借了它。", "return a book · 归还图书"),
      readingWordNote("journey", "The same book would now begin a new journey in another school bag.", "同一本书即将在另一个书包里开始新的旅程。", "begin a journey · 开始一段旅程")
    ];
    case -7: return [
      readingWordNote("colleague", "Before lunch, her colleague asked her to send a message about a small meeting.", "午饭前，同事请她发送一条小型会议的通知。", "ask a colleague · 请教一位同事"),
      readingWordNote("schedule", "She checked the schedule and wrote a new message.", "她核对日程后，重新写了一条消息。", "check the schedule · 查看日程"),
      readingWordNote("clear", "Nora learned that a short message could still be clear.", "Nora 明白了，简短的消息也可以表达清楚。", "a clear message · 清楚的消息")
    ];
    case -8: return [
      readingWordNote("spare", "His sister had told him to carry a spare pencil, just in case.", "姐姐告诉他，多带一支备用铅笔，以备不时之需。", "a spare pencil · 一支备用铅笔"),
      readingWordNote("offer", "Leo offered her his spare pencil.", "Leo 主动把备用铅笔借给她。", "offer someone something · 主动向某人提供某物"),
      readingWordNote("branch", "A girl beside Leo broke her pencil while drawing the long branches.", "Leo 旁边的女孩画长树枝时弄断了铅笔。", "a tree branch · 一根树枝")
    ];
    case -9: return [
      readingWordNote("route", "She usually walked along it after work, so she had to find another route.", "她平时下班沿这条路走，因此这次必须找另一条路线。", "find another route · 找另一条路线"),
      readingWordNote("sign", "At the corner, a yellow sign showed a path through the park.", "转角处，一块黄色指示牌标出了一条穿过公园的小路。", "follow a sign · 按指示牌走"),
      readingWordNote("pond", "Then she noticed a pond behind the trees.", "随后，她注意到树后有一个池塘。", "a small pond · 一个小池塘")
    ];
    case -10: return [
      readingWordNote("presentation", "Three students had to give a class presentation about saving water.", "三名学生需要在班上做一次关于节约用水的展示。", "give a presentation · 做展示"),
      readingWordNote("arrange", "They decided to arrange the talk in that order.", "他们决定按那个顺序组织发言。", "arrange the talk · 安排发言内容"),
      readingWordNote("practice", "During practice, Tom noticed that his chart was hard to read from the back of the room.", "练习时，Tom 发现从教室后排很难看清他的图表。", "during practice · 在练习时")
    ];
    case -11: return [
      readingWordNote("urgent", "Jin worried that he might miss an urgent request.", "Jin 担心自己可能错过紧急请求。", "an urgent request · 紧急请求"),
      readingWordNote("request", "Jin worried that he might miss an urgent request.", "Jin 担心自己可能错过紧急请求。", "respond to a request · 回应请求"),
      readingWordNote("break", "He simply needed a short break that was actually a break.", "他只是需要一次真正能休息的短暂午休。", "take a short break · 短暂休息")
    ];
    case -12: return [
      readingWordNote("patch", "The patch reminded her of the afternoon whenever she went shopping.", "每次购物时，那块补丁都会让她想起那个下午。", "a cloth patch · 一块布补丁"),
      readingWordNote("needle", "Instead of doing all the work, Mei let Sara guide the needle.", "Mei 没有独自包办，而是让 Sara 自己引导针的走向。", "a needle and thread · 针线"),
      readingWordNote("thread", "They chose bright thread so that the repair would be visible.", "她们选择亮色线，让修补的地方能被看见。", "bright thread · 亮色的线")
    ];
    case -13: return [
      readingWordNote("notice", "The notice did not mention the small green sticker under the bottle.", "通知没有提到瓶底那张绿色小贴纸。", "put up a notice · 张贴通知"),
      readingWordNote("owner", "The owner should be able to tell us something about it", "失主应当能告诉我们一些物品的特征。", "the owner of the bottle · 瓶子的主人"),
      readingWordNote("describe", "She described both the silver colour and the green sticker before Amir showed her the bottle.", "Amir 出示瓶子前，她已说出了银色外观和绿色贴纸这两个特征。", "describe an object · 描述一个物品")
    ];
    case -14: return [
      readingWordNote("replacement", "Rather than promise an immediate replacement without checking, she contacted the delivery team first.", "她没有未经核实就承诺立刻换货，而是先联系了送货团队。", "an immediate replacement · 立即更换的物品"),
      readingWordNote("label", "Grace checked the order and realised that the warehouse label was wrong.", "Grace 核对订单后，意识到仓库标签出了错。", "a warehouse label · 仓库标签"),
      readingWordNote("prevent", "Solving one complaint mattered, but preventing the same mistake from happening again mattered too.", "解决一宗投诉很重要，防止相同错误再次发生也同样重要。", "prevent a mistake · 防止错误")
    ];
    case -15: return [
      readingWordNote("experiment", "Their report included the conditions, the measurements, and a suggestion for repeating the experiment.", "报告包含实验条件、测量结果和重复实验的建议。", "repeat an experiment · 重复一项实验"),
      readingWordNote("measure", "Each afternoon, they measured the plants and wrote down the height.", "每天下午，他们测量植物并记下高度。", "measure the height · 测量高度"),
      readingWordNote("condition", "Their report included the conditions, the measurements, and a suggestion for repeating the experiment.", "报告包含实验条件、测量结果和重复实验的建议。", "experimental conditions · 实验条件")
    ];
    case -16: return [
      readingWordNote("agenda", "Theo suggested sending a short agenda before the next meeting.", "Theo 建议下次开会前先发送一份简短议程。", "send an agenda · 发送议程"),
      readingWordNote("responsible", "At the meeting, Theo wrote down each agreement, the person responsible, and a realistic deadline.", "会上，Theo 记下每项约定、负责人和切实可行的截止日期。", "the person responsible · 负责人"),
      readingWordNote("deadline", "At the meeting, Theo wrote down each agreement, the person responsible, and a realistic deadline.", "会上，Theo 记下每项约定、负责人和切实可行的截止日期。", "a realistic deadline · 切实可行的截止日期")
    ];
    case -17: return [
      readingWordNote("budget", "Its members had a small budget for paper, thread, and a sign.", "社员们只有一小笔预算，用于购买纸、线和制作标牌。", "a small budget · 一小笔预算"),
      readingWordNote("compare", "Lin suggested comparing the cost of three simple designs before choosing one.", "Lin 建议先比较三种简单设计的成本，再做选择。", "compare the cost · 比较成本"),
      readingWordNote("expense", "The club recorded its income and expenses before deciding how many books it could buy.", "社团先记录收入和支出，再决定能买多少本书。", "income and expenses · 收入和支出")
    ];
    case -18: return [
      readingWordNote("feedback", "Maya kept the specific feedback with her notes for the next report.", "Maya 把这条具体反馈和笔记放在一起，供下次写报告时参考。", "specific feedback · 具体反馈"),
      readingWordNote("specific", "Maya kept the specific feedback with her notes for the next report.", "Maya 把这条具体反馈和笔记放在一起，供下次写报告时参考。", "be specific · 说得具体"),
      readingWordNote("review", "After her first month at the company, Maya asked a colleague to review a report she had written.", "在公司工作满一个月后，Maya 请同事审阅自己写的一份报告。", "review a report · 审阅报告")
    ];
    default: return [];
  }
}
