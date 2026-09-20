/// conatus_workflow：编排引擎（实验性）。
///
/// 本包处于早期探索阶段，API 可能在没有 major 版本号变更的情况下发生
/// 破坏性改动。请勿在生产环境依赖它。
///
/// 已落地：流程定义词汇 —— [WorkflowDefinition] / [WorkflowInput] /
/// [WorkflowNode] 三种节点（[ToolNode] / [AgentNode] / [SubWorkflowNode]），
/// 声明式 JSON 序列化（[WorkflowNode.fromJson] 按 `type` 分派，非法输入
/// 抛 [WorkflowException]）；运行词汇 —— [WorkflowRun] / [RunNode] /
/// [RunStatus] / [RunNodeStatus]，可序列化；执行引擎 —— DAG 遍历、暂停 /
/// 恢复 / 重跑 / 取消与事件流（[WorkflowEngine] / [WorkflowEngineImpl]，
/// 节点执行经 [NodeExecutor] 接到工具 / 成员 / 子流程）；8 个面向模型的
/// 流程工具（[provideWorkflowTools]）与语音播报 seam（[WorkflowVoice]）。
library;

export 'src/automation.dart'
    show
        Automation,
        ConditionTrigger,
        CronTrigger,
        EventTrigger,
        ManualTrigger,
        Trigger;
export 'src/constraint.dart'
    show
        BudgetConstraint,
        Constraint,
        ConstraintContext,
        MutexConstraint,
        PermissionConstraint,
        TimeWindowConstraint;
export 'src/definition.dart' show WorkflowDefinition, WorkflowInput;
export 'src/engine.dart'
    show
        NodeExecutor,
        RunCompleted,
        RunFailed,
        RunNodeCompleted,
        RunNodeFailed,
        RunNodeSkipped,
        RunNodeStarted,
        RunStarted,
        WorkflowEngine,
        WorkflowEvent,
        WorkflowRegistered;
export 'src/engine_impl.dart' show WorkflowEngineImpl;
export 'src/errors.dart' show WorkflowException;
export 'src/executor.dart' show buildNodeExecutor;
export 'src/hooks.dart'
    show WorkflowHooks, kWorkflowRunEvent, restoreWorkflowRun;
export 'src/node.dart' show AgentNode, SubWorkflowNode, ToolNode, WorkflowNode;
export 'src/post_action.dart'
    show
        ChainAction,
        CompositeAction,
        NotifyAction,
        PostAction,
        PostContext,
        RecordAction;
export 'src/provider.dart' show WorkflowContext, provideWorkflow;
export 'src/refs.dart'
    show evaluateCondition, resolveArguments, resolveReference, resolveValue;
export 'src/run.dart' show WorkflowRun;
export 'src/run_node.dart' show RunNode;
export 'src/scheduler.dart'
    show
        AutomationBlocked,
        AutomationRegistered,
        AutomationTriggered,
        SchedulerContext,
        SchedulerEvent,
        WorkflowScheduler,
        provideWorkflowScheduler;
export 'src/scheduler_impl.dart' show WorkflowSchedulerImpl;
export 'src/status.dart' show RunNodeStatus, RunStatus;
export 'src/store.dart' show InMemoryWorkflowStore, WorkflowStore;
export 'src/tools/workflow_control_tools.dart'
    show
        WorkflowCancelTool,
        WorkflowPauseTool,
        WorkflowRerunTool,
        WorkflowResumeTool;
export 'src/tools/workflow_tools.dart'
    show
        WorkflowCreateTool,
        WorkflowListTool,
        WorkflowRunTool,
        WorkflowStatusTool,
        provideWorkflowTools;
export 'src/voice.dart'
    show
        WorkflowVoice,
        workflowCreatedMessage,
        workflowFailedMessage,
        workflowProgressMessage,
        workflowResultMessage,
        workflowUpdatedMessage;
