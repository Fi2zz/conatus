/// conatus_team：多智能体协作（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 已落地：核心词汇（[TeamRole] / [Teammate] / [TeamTask] / [AgentTeam]
/// 接口）与默认实现（[AgentTeamImpl] / [provideAgentTeam]）+ 任务板
/// （[TeamBoard]，DAG 依赖 + CAS 乐观锁）+ 成员运行时（[MemberRuntime]，
/// 独立 Session + AgentLoop + 取消信号）+ 四种协作模式（顺序 / 并发 /
/// 群聊 / Maker-Checker，见 patterns/）+ 10 个面向模型的团队工具
/// （见 tools/，[provideTeamTools] 一键注册）+ 四条可选运行时 seam
/// （[TeamHooks]：任务追踪 / 会话 / 审批 / 遥测）。
library;

export 'src/team.dart';
