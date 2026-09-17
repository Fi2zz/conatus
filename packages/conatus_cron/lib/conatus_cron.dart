/// conatus 的定时任务插件：按 at / every / daily / cron 规则调度任务。
///
/// 语义忠实移植 dsh-cron：到点把任务提示以固定 framing 交付给宿主注入的
/// [CronDelivery] 端口执行，运行记录持久化（重启不重发已消费时段，daily 错过
/// 当天时段补发一次），模型可用 `cron_list` / `cron_add` / `cron_update` /
/// `cron_remove` / `cron_history` 管理任务。任务运行结束后由装配方调用
/// [CronRuntime.finishRun] 推进记录并发系统通知。
///
/// ```dart
/// final service = provideCron(ctx,
///     storage: JsonCronStorage(tasksPath: tasksFile, historyPath: historyFile));
/// provideCronTools(ctx);
/// final runtime = provideCronRuntime(ctx, deliver: (recordId, framing) async {
///   // 把 framing 投递进目标会话；返回 false 表示暂时无法投递。
///   return true;
/// });
/// ```
library;

export 'src/cron.dart' show CronContext, CronService, provideCron;
export 'src/cron_book.dart' show CronHistoryBook;
export 'src/cron_edit_tools.dart'
    show CronAddTool, CronRemoveTool, CronUpdateTool;
export 'src/cron_errors.dart' show CronErrorCode, CronException;
export 'src/cron_history.dart'
    show CronRecordRef, CronRunRecord, decodeCronInstant, decodeCronInt;
export 'src/cron_message.dart' show buildTaskView, renderTaskMessage;
export 'src/cron_notify.dart' show CronNotifier, systemCronNotifier;
export 'src/cron_parse.dart'
    show
        CronExpression,
        cronMatches,
        nextCronSlot,
        parseCronExpression,
        parseCronField;
export 'src/cron_registry.dart' show CronTaskRegistry;
export 'src/cron_rules.dart'
    show
        CronTaskInput,
        dueSlot,
        generateTaskId,
        kCronRuleKeys,
        nextRunAtOf,
        taskEnabled,
        taskRuleKind,
        validateTaskInput;
export 'src/cron_runtime.dart'
    show CronDelivery, CronRuntime, CronRuntimeOptions, kDefaultCronTickSeconds;
export 'src/cron_runtime_provider.dart'
    show CronRuntimeContext, provideCronRuntime;
export 'src/cron_storage.dart'
    show CronRunStamp, CronStorage, CronStorageSnapshot;
export 'src/cron_tool_results.dart'
    show cronErrorResult, cronInternalResult, cronSuccessResult;
export 'src/cron_tools.dart'
    show CronHistoryTool, CronListTool, provideCronTools;
export 'src/cron_types.dart'
    show
        CronRuleKind,
        CronRunStatus,
        CronTask,
        CronTaskOrigin,
        CronTaskView,
        formatCronInstant,
        kCronDailyPattern,
        kCronExcerptLength,
        kCronMaxHistory,
        kCronMinEverySeconds,
        kCronStorageVersion,
        kCronTaskIdPattern;
export 'src/cron_update.dart'
    show
        applyTaskRules,
        cronTaskRuleValue,
        mergeTaskRules,
        normalizeCronPrompt,
        patchTouchesSchedule,
        resetCronRunState,
        resolveCronPrompt;
export 'src/json_cron_storage.dart' show JsonCronStorage;
