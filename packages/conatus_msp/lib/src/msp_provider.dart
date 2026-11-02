import 'dart:async';

import 'package:conatus_core/conatus_core.dart';

import 'msp_node.dart';

extension MspContext on Context {
  MspNode get msp => require<MspNode>('msp');
}

MspNode provideMsp(Context ctx, MspNode node) {
  ctx.provide('msp', node);
  ctx.onDispose(() => unawaited(node.stop()));
  return node;
}
