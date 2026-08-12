// src/context.js
// Formats structured novel/project context, reviewed continuity state, and long-term Story Memory.

const CREATIVE_CONTEXT_CHAR_BUDGET = 24000;

const LIMITS = {
  synopsis: 4200,
  outline: 6000,
  world: 6200,
  notes: 3000,
  timeline: 4200,
  foreshadow: 4200,
  relations: 3800,
  threads: 4800,
  memories: 6500,
  chapter: 4600,
  manuscript: 7600,
  character: 2600,
  previousChapter: 3200
};

function text(value, limit = 4000) {
  if (value == null) return "";
  const raw = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  const clean = raw.trim();
  if (!clean) return "";
  return clean.length > limit ? `${clean.slice(0, limit)}\n[内容已截断]` : clean;
}

function section(title, value, limit) {
  const body = text(value, limit);
  return body ? `## ${title}\n${body}` : "";
}

function continuityStateFor(name, continuityContext) {
  if (!name || !Array.isArray(continuityContext?.characterStates)) return "";
  const normalized = String(name).trim().toLowerCase();
  const match = continuityContext.characterStates.find((item) => String(item?.name || "").trim().toLowerCase() === normalized);
  return text(match?.state, 900);
}

function characterText(character, continuityContext) {
  if (typeof character === "string") {
    const name = text(character, 120);
    if (!name) return "";
    const reviewedState = continuityStateFor(name, continuityContext);
    return `### ${name}${reviewedState ? `\n当前状态：${reviewedState}` : ""}`;
  }
  if (!character || typeof character !== "object") return "";

  const name = text(character.name || character.title || character.id || "人物", 120);
  const reviewedState = continuityStateFor(name, continuityContext);
  const preferred = [
    ["身份", character.role || character.identity || character.job],
    ["性格", character.personality],
    ["外貌", character.appearance],
    ["核心目标", character.goal || character.goals],
    ["人物秘密", character.secret || character.secrets],
    ["当前状态", reviewedState || character.currentState || character.state],
    ["说话特点", character.voice || character.speech],
    ["备注", character.notes || character.description || character.note || character.bio]
  ];
  const lines = preferred
    .map(([label, value]) => [label, text(value, 900)])
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}：${value}`);

  if (!lines.length) {
    const fallback = { ...character };
    delete fallback.id;
    return `### ${name}\n${text(fallback, LIMITS.character)}`;
  }
  return `### ${name}\n${text(lines.join("\n"), LIMITS.character)}`;
}

function worldText(project) {
  if (!project || typeof project !== "object") return "";
  const structured = [
    ["世界观概述", project.worldOverview],
    ["世界规则", project.worldRules],
    ["地点", project.locations],
    ["势力 / 组织", project.factions],
    ["重要物品", project.importantItems]
  ]
    .map(([label, value]) => [label, text(value, 1800)])
    .filter(([, value]) => value)
    .map(([label, value]) => `${label}：\n${value}`)
    .join("\n\n");

  return structured || text(project.world, LIMITS.world);
}

function memoryText(memory) {
  if (!memory || typeof memory !== "object") return "";
  const content = text(memory.content, 1200);
  if (!content) return "";
  const type = text(memory.type || "事件", 60);
  const importance = Math.max(1, Math.min(5, Number(memory.importance) || 3));
  const characters = Array.isArray(memory.characters) ? memory.characters.map((item) => text(item, 80)).filter(Boolean) : [];
  const tags = Array.isArray(memory.tags) ? memory.tags.map((item) => text(item, 80)).filter(Boolean) : [];
  const meta = [
    characters.length ? `人物：${characters.join("、")}` : "",
    tags.length ? `标签：${tags.join("、")}` : "",
    memory.status === "resolved" ? "状态：已解决" : ""
  ].filter(Boolean).join("；");
  return `- [${type}｜重要度${importance}] ${content}${meta ? `（${meta}）` : ""}`;
}

function threadText(item) {
  if (!item || typeof item !== "object") return "";
  const title = text(item.title, 140);
  const detail = text(item.detail, 900);
  if (!title || !detail) return "";
  const typeLabels = {
    foreshadow: "伏笔",
    event: "持续事件",
    object: "物品",
    relationship: "关系"
  };
  const type = typeLabels[String(item.type || "").toLowerCase()] || "连续性";
  return `- [${type}] ${title}：${detail}`;
}

function joinWithinBudget(header, sections) {
  let output = header.trim();
  for (const item of sections.filter(Boolean)) {
    const separator = "\n\n";
    const remaining = CREATIVE_CONTEXT_CHAR_BUDGET - output.length - separator.length;
    if (remaining <= 0) break;

    if (item.length <= remaining) {
      output += separator + item;
      continue;
    }

    if (remaining >= 500) {
      output += separator + item.slice(0, Math.max(0, remaining - 20)) + "\n[上下文预算已用尽]";
    }
    break;
  }
  return output;
}

export function buildCreativeContextMessage(context, memoryContext = null, continuityContext = null) {
  if ((!context || typeof context !== "object")
    && (!memoryContext || typeof memoryContext !== "object")
    && (!continuityContext || typeof continuityContext !== "object")) return "";

  const safeContext = context && typeof context === "object" ? context : {};
  const project = safeContext.project && typeof safeContext.project === "object" ? safeContext.project : {};
  const chapter = safeContext.chapter && typeof safeContext.chapter === "object" ? safeContext.chapter : {};
  const characters = Array.isArray(safeContext.characters) ? safeContext.characters.slice(0, 8) : [];
  const memories = Array.isArray(memoryContext?.items) ? memoryContext.items.slice(0, 16) : [];
  const openThreads = Array.isArray(continuityContext?.openThreads) ? continuityContext.openThreads.slice(0, 20) : [];
  const reviewedChapterSummary = text(continuityContext?.chapterSummary, 2600);
  const reviewedPreviousChapterSummary = text(continuityContext?.previousChapterSummary, LIMITS.previousChapter);

  const identity = section("作品", [
    project.name ? `名称：${text(project.name, 160)}` : "",
    project.description ? `定位：${text(project.description, 900)}` : ""
  ].filter(Boolean).join("\n"), 1200);

  const manuscriptSection = chapter.manuscriptExcerpt
    ? section(
      "当前章节正文末尾（最高优先级）",
      `这是已经写入正式正文的最近内容。续写时必须直接承接其叙事视角、语气、人物位置、身体状态和最后发生的动作；不要重复已有段落。\n${chapter.manuscriptExcerpt}`,
      LIMITS.manuscript
    )
    : "";

  const currentChapter = section("当前章节计划与状态", [
    chapter.title || chapter.name ? `标题：${text(chapter.title || chapter.name, 180)}` : "",
    reviewedChapterSummary
      ? `连续性摘要：${reviewedChapterSummary}`
      : chapter.summary ? `摘要：${text(chapter.summary, 2600)}` : "",
    chapter.notes ? `本章目标/备注：${text(chapter.notes, 1800)}` : "",
    chapter.targetWords ? `目标字数：${chapter.targetWords}` : ""
  ].filter(Boolean).join("\n"), LIMITS.chapter);

  const characterSection = characters.length
    ? `## 当前相关人物（高优先级）\n${characters.map((character) => characterText(character, continuityContext)).filter(Boolean).join("\n\n")}`
    : "";

  const threadLines = openThreads.map(threadText).filter(Boolean).join("\n");
  const threadSection = threadLines
    ? section("尚未解决的伏笔与持续事件", `这些事项仍需保持一致，除非正文明确解决，否则不要遗忘或擅自改写。\n${threadLines}`, LIMITS.threads)
    : "";

  const memoryLines = memories.map(memoryText).filter(Boolean).join("\n");
  const memorySection = memoryLines
    ? section("长期故事记忆", `以下是跨章节仍需保持一致的重要事实。与用户本轮明确要求冲突时，以用户最新要求为准。\n${memoryLines}`, LIMITS.memories)
    : "";

  // The order below is intentional. Sections closer to the current writing task are
  // placed first so they survive the shared context budget before broad background.
  const sections = [
    identity,
    manuscriptSection,
    currentChapter,
    characterSection,
    section("人物关系", project.relations, LIMITS.relations),
    threadSection,
    section("世界观与硬性规则", worldText(project), LIMITS.world),
    section("上一章摘要", reviewedPreviousChapterSummary || safeContext.previousChapterSummary, LIMITS.previousChapter),
    memorySection,
    section("时间线", project.timeline, LIMITS.timeline),
    section("人工伏笔记录", project.foreshadow, LIMITS.foreshadow),
    section("故事梗概", project.synopsis, LIMITS.synopsis),
    section("总体大纲", project.outline, LIMITS.outline),
    section("其他创作备注", project.notes, LIMITS.notes)
  ];

  const usefulSections = sections.filter(Boolean);
  if (!usefulSections.length) return "";

  const header = [
    "# 当前小说创作上下文",
    "按出现顺序处理优先级：越靠前越接近当前写作事实。正式正文与已确认的连续性状态优先于宽泛总纲。除非用户明确要求修改既有设定，否则保持人物、事件和世界规则一致；不要在正文中机械复述这些资料。"
  ].join("\n\n");

  return joinWithinBudget(header, usefulSections);
}
