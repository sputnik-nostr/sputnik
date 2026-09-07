import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/models/nostr_payment_target.dart';

NostrEvent _eventWithTags(List<List<String>> tags) {
  return NostrEvent(
    id: 'id',
    pubkey: 'pubkey',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    kind: 10133,
    tags: tags,
    content: '',
    sig: 'sig',
  );
}

void main() {
  test('reads payto tags into payment targets, ignoring other tags', () {
    final event = _eventWithTags([
      ['payto', 'bitcoin', 'bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k'],
      ['p', 'someunrelatedtag'],
      ['payto', 'unknowntype', 'l7tbta5b9xze6ckkfc99uohzxd009b0r'],
      ['payto', 'incomplete'],
    ]);

    expect(paymentTargetsFromEvent(event), [
      const NostrPaymentTarget(
        type: 'bitcoin',
        address: 'bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k',
      ),
      const NostrPaymentTarget(
        type: 'unknowntype',
        address: 'l7tbta5b9xze6ckkfc99uohzxd009b0r',
      ),
    ]);
  });

  test('builds a direct URI for widely deployed schemes', () {
    const target = NostrPaymentTarget(
      type: 'bitcoin',
      address: 'bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k',
    );
    expect(
      target.launchUri.toString(),
      'bitcoin:bc1qxq66e0t8d7ugdecwnmv58e90tpry23nc84pg9k',
    );
  });

  test('falls back to payto:// for unrecognized schemes', () {
    const target = NostrPaymentTarget(
      type: 'unknowntype',
      address: 'l7tbta5b9xze6ckkfc99uohzxd009b0r',
    );
    expect(
      target.launchUri.toString(),
      'payto://unknowntype/l7tbta5b9xze6ckkfc99uohzxd009b0r',
    );
  });
}
