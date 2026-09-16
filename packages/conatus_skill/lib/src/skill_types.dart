/// 技能的数据词汇：来源标签、摘要、候选、完整定义与资源基址。
library;

/// 来源 `project-conatus`：项目根下的 `.conatus/skills`。
const String kSkillSourceProjectConatus = 'project-conatus';

/// 来源 `project-agents`：项目根下的 `.agents/skills`。
const String kSkillSourceProjectAgents = 'project-agents';

/// 来源 `custom`：调用方显式给出的目录。
const String kSkillSourceCustom = 'custom';

/// 来源 `user-conatus`：`$CONATUS_HOME/skills`（缺省 `~/.conatus/skills`）。
const String kSkillSourceUserConatus = 'user-conatus';

/// 来源 `user-agents`：`$CONATUS_AGENTS_HOME/skills`（缺省 `~/.agents/skills`）。
const String kSkillSourceUserAgents = 'user-agents';

/// 来源 `runtime`：由宿主代码用 [SkillRegistration] 直接注册的技能。
const String kSkillSourceRuntime = 'runtime';

/// provider 名 `filesystem`：目录发现型 provider。
const String kSkillFilesystemProvider = 'filesystem';

/// provider 名 `runtime`：注册表内置的运行时技能。
const String kSkillRuntimeProvider = 'runtime';

/// 运行时技能在层内排序中的权重：排在项目发现根（100/200）之后、自定义与
/// 用户根（300/400/500）之前，因此项目声明可以覆盖宿主内建技能。
const int kSkillRuntimeRank = 250;

final RegExp _skillNamePattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// [name] 是否是合法的技能名：小写字母与数字，用 `-` 分隔。
bool isSkillName(String name) => _skillNamePattern.hasMatch(name);

/// 一条技能的模型可见摘要。
class SkillSummary {
  /// 构造摘要。
  const SkillSummary({
    required this.name,
    required this.description,
    required this.source,
    required this.provider,
    this.whenToUse,
    this.modelInvocable = true,
    this.path,
  });

  /// 模型用来寻址的名字。
  final String name;

  /// 一行路由描述，出现在技能目录里。
  final String description;

  /// 适用时机的补充说明；`null` 表示未声明。
  final String? whenToUse;

  /// 来源标签，仅用于展示与诊断。
  final String source;

  /// 提供该技能的 provider 名。
  final String provider;

  /// 模型是否可以调用 `skill` 工具加载它。
  final bool modelInvocable;

  /// 技能文件路径（发现型 provider 才有）。
  final String? path;

  /// 规范 JSON 投影。
  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        if (whenToUse != null) 'whenToUse': whenToUse,
        'source': source,
        'provider': provider,
        'modelInvocable': modelInvocable,
        if (path != null) 'path': path,
      };
}

/// provider 产出的候选：摘要 + 层内排序权重。
class SkillCandidate {
  /// 构造候选。
  const SkillCandidate({required this.summary, this.rank = 0});

  /// 候选摘要。
  final SkillSummary summary;

  /// 层内权重：数值小的先赢下同名。
  final int rank;
}

/// 运行时技能的注册请求。
class SkillRegistration {
  /// 构造注册请求。
  const SkillRegistration({
    required this.name,
    required this.description,
    this.whenToUse,
    this.content = '',
    this.resourceBase,
  });

  /// 技能名。
  final String name;

  /// 一行描述。
  final String description;

  /// 适用时机的补充说明。
  final String? whenToUse;

  /// 技能正文（去 frontmatter 的指令文本）。
  final String content;

  /// 资源基址。
  final SkillResourceBase? resourceBase;

  /// 注册表里的摘要投影。
  SkillSummary toSummary() => SkillSummary(
        name: name,
        description: description,
        whenToUse: whenToUse,
        source: kSkillSourceRuntime,
        provider: kSkillRuntimeProvider,
      );

  /// 注册表里的完整定义。
  SkillDefinition toDefinition() => SkillDefinition(
        summary: toSummary(),
        content: content,
        resourceBase: resourceBase,
      );
}

/// 一次 `skill` 调用的完整载荷：摘要 + 正文 + 资源基址。
class SkillDefinition {
  /// 构造定义。
  const SkillDefinition({
    required this.summary,
    required this.content,
    this.resourceBase,
  });

  /// 摘要。
  final SkillSummary summary;

  /// 技能正文。
  final String content;

  /// 资源基址；`null` 表示由 provider 自行管理。
  final SkillResourceBase? resourceBase;
}

/// 技能附带资源的基址。
sealed class SkillResourceBase {
  /// 供子类继承。
  const SkillResourceBase();
}

/// 资源位于某个目录：相对路径按它解析。
final class SkillDirectoryResource extends SkillResourceBase {
  /// 构造目录基址。
  const SkillDirectoryResource(this.path);

  /// 目录路径。
  final String path;
}

/// 资源位于某个 URL：相对地址按它解析。
final class SkillUrlResource extends SkillResourceBase {
  /// 构造 URL 基址。
  const SkillUrlResource(this.url);

  /// 基址 URL。
  final String url;
}

/// 资源由 provider 自行描述。
final class SkillOpaqueResource extends SkillResourceBase {
  /// 构造描述型基址。
  const SkillOpaqueResource(this.description);

  /// 面向模型的说明。
  final String description;
}
