/// conatus_ontology：自进化本体层。
///
/// 显式、版本化的语义本体（Term / Mapping / Constraint / Evidence），
/// 从执行轨迹持续进化：接地构建、TypedEdits 局部更新、backbone-conditional
/// 配对评估门控、人类可回滚。适配 EvoOntology（arXiv:2609.15779）。
///
/// ⚠️ 实验性：API 可能在没有 major 版本号变更的情况下发生破坏性改动。
library;

export 'src/benchmark/adapter.dart' show EvolutionAdapter, RolloutResult;
export 'src/benchmark/bird.dart' show BirdAdapter;
export 'src/builder/builder.dart' show BuildResult, buildOntology;
export 'src/builder/extractor.dart' show describeSources, extractCandidates, parseTerms;
export 'src/builder/grounding.dart'
    show
        GroundingResult,
        constraintHolds,
        groundTerm,
        proposeConstraints,
        proposeMappings;
export 'src/builder/source.dart' show DataColumn, DataSource;
export 'src/evolver/attribution.dart'
    show
        Attribution,
        AttributionEngine,
        AttributionTarget,
        parseAttributions;
export 'src/evolver/diagnosis.dart'
    show SemanticDiagnosis, SemanticError, diagnose, parseDiagnosis;
export 'src/evolver/evaluator.dart'
    show BackboneConfig, ConditionalEvalResult;
export 'src/evolver/evolver.dart'
    show OntologyVariant, evolveVariant;
export 'src/evolver/generic_evolver.dart'
    show
        EvolutionOutcome,
        Evolver,
        EvolverVariant,
        OntologyEvolver;
export 'src/evolver/paired_evaluator.dart' show PairedEvaluator;
export 'src/evolver/patcher.dart' show generateEdits, parseTypedEdits;
export 'src/mcp/tools.dart' show registerOntologyTools;
export 'src/ontology/apply.dart' show applyEdits;
export 'src/ontology/edit_validator.dart' show TypedEditValidator;
export 'src/ontology/edits.dart'
    show
        AddNode,
        AddReference,
        AddRelation,
        MergeTerms,
        RemoveNode,
        RemoveReference,
        RemoveRelation,
        SplitTerm,
        TypedEdit,
        UpdateNodeFields;
export 'src/ontology/layer.dart' show OntologyLayer;
export 'src/ontology/node.dart'
    show Constraint, Evidence, Mapping, OntologyNode, Term;
export 'src/ontology/relation.dart'
    show SemanticRelation, StructuralReference;
export 'src/ontology/schema.dart'
    show
        OntologySchema,
        SchemaField,
        SchemaFieldType,
        ValidationResult;
export 'src/runtime/browse.dart' show NodeSummary, browseLayer;
export 'src/runtime/manifest.dart' show buildManifest;
export 'src/runtime/resolve.dart' show ResolvedSemantics, resolveSemantics;
export 'src/runtime/service.dart'
    show
        OntologyContext,
        OntologyEvent,
        OntologyPublished,
        OntologyRejected,
        OntologyService,
        provideOntology;
export 'src/runtime/service_default.dart' show DefaultOntologyService;
export 'src/store/database_store.dart' show DatabaseStore;
export 'src/store/memory_store.dart' show MemoryStore;
export 'src/store/store.dart' show OntologyStore;
export 'src/tools/ontology_tools.dart'
    show
        BrowseSemanticsTool,
        OntologyManifestTool,
        ResolveSemanticsTool;
