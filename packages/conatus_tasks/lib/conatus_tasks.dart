/// task 插件：conatus 的任务中心（Task Center）。
///
/// Task Center 是运行时的任务追踪中枢：只回答「现在有哪些任务在跑、各自
/// 什么状态、能不能取消」，不负责调度与执行。任务由 Agent Loop /
/// sub-agent / shell / schedule 经 [provideTaskTracking] 的装饰器自动
/// 创建（`parentTaskId` 组成任务树），状态以 `task/changed` 事件持久化到
/// 会话（整值替换，恢复时未完成任务标记为 failed），模型侧只有
/// `list_tasks` / `cancel_task` 两个工具。
///
/// ```dart
/// final tasks = provideTaskCenter(ctx);
/// provideTaskTracking(ctx);        // 挂 Agent Loop / spawn_agent 追踪
/// ctx.tools.call(const ToolCall(name: 'list_tasks'));
/// ```
library;

export 'src/task.dart'
    show
        Task,
        TaskException,
        TaskKind,
        TaskStatus,
        kTaskEvent,
        kTaskStaleReason,
        restoreTaskState;
export 'src/task_center.dart' show TaskCenter, TasksContext;
export 'src/task_center_default.dart' show DefaultTaskCenter;
export 'src/task_center_provider.dart'
    show provideTaskCenter, provideTaskTracking;
export 'src/task_tools.dart'
    show
        CancelTaskTool,
        ListTasksTool,
        describeTasks,
        kCancelTasksToolName,
        kListTasksToolName;
export 'src/task_tracking.dart'
    show
        TaskTracking,
        TrackingShellExecutor,
        kSpawnAgentToolName,
        trackScheduleDelivery;
