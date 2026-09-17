/// conatus_team 的核心词汇与默认实现桶。
///
/// 这里只做转出：类型与抽象分布在 [teammate] / [team_task] / [team_events]
/// / [agent_team]；默认实现与成员运行时 / 任务板 / 服务入口 / 运行时
/// hook 分布在 [team_impl] / [team_member_runtime] / [team_board] /
/// [team_hooks] / [team_task_tracker]；协作模式接口在 [team_pattern]，
/// 四种内置模式在 patterns/；面向模型的团队工具在 tools/
/// （[provideTeamTools] 一次性注册）。
library;

export 'agent_team.dart' show AgentTeam, TeamException;
export 'patterns/concurrent.dart' show ConcurrentPattern;
export 'patterns/group_chat.dart' show GroupChatPattern;
export 'patterns/maker_checker.dart' show MakerCheckerPattern;
export 'patterns/sequential.dart' show SequentialPattern;
export 'team_board.dart' show TeamBoard;
export 'team_events.dart'
    show
        AgentTeamEvent,
        TeamMessageSent,
        TeamTaskChanged,
        TeamTaskCreated,
        TeammateSpawned,
        TeammateStatusChanged;
export 'team_hooks.dart' show TeamHooks;
export 'team_impl.dart' show AgentTeamImpl, TeamContext, provideAgentTeam;
export 'team_member_runtime.dart'
    show MemberRuntime, TeammateMutation, TeamTurn;
export 'team_pattern.dart' show TeamPattern;
export 'team_task.dart' show TeamTask, TeamTaskStatus;
export 'team_task_tracker.dart' show TeamTaskTracker;
export 'team_voice.dart'
    show
        TeamVoice,
        memberRemovedMessage,
        progressMessage,
        resultMessage,
        teamCreatedMessage;
export 'teammate.dart' show TeamRole, Teammate, TeammateStatus;
export 'tools/team_member_tools.dart'
    show
        FollowupTaskTool,
        InterruptAgentTool,
        ListAgentsTool,
        SendMessageTool,
        SpawnTeammateTool,
        WaitAgentTool;
export 'tools/team_task_tools.dart'
    show
        TeamTaskCreateTool,
        TeamTaskGetTool,
        TeamTaskListTool,
        TeamTaskUpdateTool;
export 'tools/team_tools.dart' show provideTeamTools;
