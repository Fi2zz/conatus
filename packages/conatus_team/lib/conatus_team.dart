/// conatus_team：多智能体协作（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 已落地：核心词汇（[TeamRole] / [Teammate] / [TeamTask] / [AgentTeam]
/// 接口）与默认实现（[AgentTeamImpl] / [provideAgentTeam]）+ 任务板
/// （[TeamBoard]，DAG 依赖 + CAS 乐观锁）+ 成员运行时（[MemberRuntime]，
/// 独立 Session + AgentLoop + 取消信号）。协作模式与团队工具将在后续
/// 步骤加入，见 `.handoffs/HANDOFF-6.md` 第 12 节的实现顺序。
library;

export 'src/team.dart';
