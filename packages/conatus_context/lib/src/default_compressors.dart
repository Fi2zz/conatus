/// 内置压缩器集合。
library;

import 'compressors/build_log_compressor.dart';
import 'compressors/diff_compressor.dart';
import 'compressors/json_array_compressor.dart';
import 'compressors/search_results_compressor.dart';
import 'compressors/tabular_compressor.dart';
import 'compressors/text_compressor.dart';
import 'content_compressor.dart';

/// 六类结构化内容压缩器。
List<ContentCompressor> defaultContentCompressors() =>
    const <ContentCompressor>[
      JsonArrayCompressor(),
      BuildLogCompressor(),
      SearchResultsCompressor(),
      DiffCompressor(),
      TabularCompressor(),
      TextCompressor(),
    ];
