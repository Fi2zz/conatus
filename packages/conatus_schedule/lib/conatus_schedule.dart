/// 会话本地持久提醒：把提醒写进会话事件流，并在到期后交付回同一会话。
///
/// 提醒没有独立存储：唯一权威是会话里的 `schedule/change` 事件（协议版本 1，
/// 严格解码），因此会话落盘后重启即可自动重建。模型侧由 `schedule_create` /
/// `schedule_list` / `schedule_delete` 三个工具管理提醒；到期交付由
/// [ScheduleRuntime] 驱动，并把「投递」这一步交给宿主注入的 [ScheduleDelivery]。
///
/// ```dart
/// final schedule = provideSessionSchedule(ctx, session: session, sessions: store);
/// provideScheduleTools(ctx);
/// provideScheduleRuntime(ctx, deliver: (text) async => submit(text));
/// ```
library;

export 'src/schedule.dart'
    show ScheduleContext, SessionSchedule, provideSessionSchedule;
export 'src/schedule_changes.dart'
    show
        ScheduleChange,
        ScheduleCreateChange,
        ScheduleDeleteChange,
        ScheduleDispatchChange,
        decodeScheduleChange,
        decodeScheduleId,
        decodeScheduleRecord,
        quoteScheduleId;
export 'src/schedule_create_tool.dart'
    show
        ScheduleCreateTool,
        asSafeInteger,
        kScheduleCreateKeys,
        validateCreateArgs;
export 'src/schedule_delivery.dart'
    show
        ScheduleDelivery,
        ScheduleDeliveryOutcome,
        deliverDueDecision,
        recordScheduleDispatch,
        warnSchedule;
export 'src/schedule_due.dart'
    show
        DueDecision,
        ScheduleEveryBatchDue,
        ScheduleOneShotDue,
        ScheduleWait,
        dueDecision;
export 'src/schedule_errors.dart'
    show
        ScheduleErrorCode,
        ScheduleInputException,
        ScheduleLogException,
        ScheduleOperation,
        SchedulePersistenceException;
export 'src/schedule_fold.dart'
    show allocateScheduleId, applyScheduleChanges, foldScheduleEvents;
export 'src/schedule_framing.dart'
    show renderDueFraming, renderReminderBatchFraming, renderReminderFraming;
export 'src/schedule_local_instant.dart' show resolveLocalInstant;
export 'src/schedule_recurrence.dart'
    show EveryOccurrence, resolveEveryOccurrence;
export 'src/schedule_rules.dart'
    show
        createAfterRecord,
        createAtRecord,
        createEveryRecord,
        normalizePrompt,
        scheduleView;
export 'src/schedule_runtime.dart' show ScheduleRuntime, kMaxTimerSegment;
export 'src/schedule_runtime_provider.dart'
    show ScheduleRuntimeContext, provideScheduleRuntime;
export 'src/schedule_time.dart'
    show
        CalendarParts,
        calendarInstant,
        decodeInstant,
        formatUtcInstant,
        futureInstant,
        kMaxSafeInteger,
        matchesUtcInstantShape,
        maxFourDigitYearInstant,
        minFourDigitYearInstant,
        safePositiveSeconds,
        tryParseUtcInstant;
export 'src/schedule_time_zone.dart'
    show
        canonicalTimeZone,
        loadTimeZoneData,
        parseLocalParts,
        parseOffsetInstant,
        resolveAtTarget,
        resolveLocalAt;
export 'src/schedule_tool_results.dart'
    show
        scheduleCorruptResult,
        scheduleErrorResult,
        scheduleInternalResult,
        schedulePersistenceResult,
        scheduleSuccessResult;
export 'src/schedule_tools.dart'
    show ScheduleDeleteTool, ScheduleListTool, provideScheduleTools;
export 'src/schedule_types.dart'
    show
        ScheduleDeleteResult,
        ScheduleDue,
        ScheduleFold,
        ScheduleKind,
        ScheduleRecord,
        ScheduleState,
        ScheduleView,
        kMinEveryIntervalSeconds,
        kScheduleChangeEvent,
        kScheduleChangeVersion,
        kScheduleDeliveryMode;
