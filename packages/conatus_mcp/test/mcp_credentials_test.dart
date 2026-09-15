import 'package:conatus_core/conatus_core.dart';
import 'package:conatus_credentials/conatus_credentials.dart';
import 'package:conatus_foundation/conatus_foundation.dart';
import 'package:conatus_mcp/conatus_mcp.dart';
import 'package:test/test.dart';
import 'mcp_test_support.dart';

void main() {
  late Context ctx;
  late FakeMcpServers fakes;

  setUp(() {
    ctx = Context.root();
    provideTools(ctx);
    fakes = FakeMcpServers();
  });

  tearDown(() {
    if (!ctx.disposed) ctx.dispose();
  });

  test('命中即替换，未命中或没有凭据服务时原样保留', () {
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'REMOTE_TOKEN': 's3cret'},
    );

    expect(
      resolveCredentialPlaceholders(
        <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
        credentials,
      ),
      <String, String>{'Authorization': 'Bearer s3cret'},
    );
    expect(
      resolveCredentialPlaceholders(
        <String, String>{'X': r'${MISSING}'},
        credentials,
      ),
      <String, String>{'X': r'${MISSING}'},
    );
    expect(
      resolveCredentialPlaceholders(
        <String, String>{'X': r'${REMOTE_TOKEN}'},
        null,
      ),
      <String, String>{'X': r'${REMOTE_TOKEN}'},
    );
    expect(
      resolveCredentialPlaceholders(
        <String, String>{'X': 'plain', 'Y': r'$NOT_A_PLACEHOLDER'},
        credentials,
      ),
      <String, String>{'X': 'plain', 'Y': r'$NOT_A_PLACEHOLDER'},
    );
  });

  test('provideMcp：env / headers 里的占位符解析后交给传输', () async {
    final InMemoryCredentials credentials = InMemoryCredentials(
      initial: <String, String>{'REMOTE_TOKEN': 's3cret'},
    );

    await provideMcp(
      ctx,
      <McpServerConfig>[
        McpServerConfig(
          name: 'fs',
          type: McpTransportType.stdio,
          command: 'npx',
          env: <String, String>{'TOKEN': r'${REMOTE_TOKEN}'},
        ),
        McpServerConfig(
          name: 'net',
          type: McpTransportType.http,
          url: 'https://example.com/mcp',
          headers: <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
        ),
      ],
      credentials: credentials,
      transportFactory: fakes.build,
    );

    expect(fakes.configs['fs']?.env, <String, String>{'TOKEN': 's3cret'});
    expect(
      fakes.configs['net']?.headers,
      <String, String>{'Authorization': 'Bearer s3cret'},
    );
  });

  test('provideMcp：没有凭据服务时占位符原样带过去', () async {
    await provideMcp(
      ctx,
      <McpServerConfig>[
        McpServerConfig(
          name: 'net',
          type: McpTransportType.http,
          url: 'https://example.com/mcp',
          headers: <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
        ),
      ],
      transportFactory: fakes.build,
    );

    expect(
      fakes.configs['net']?.headers,
      <String, String>{'Authorization': r'Bearer ${REMOTE_TOKEN}'},
    );
  });
}
