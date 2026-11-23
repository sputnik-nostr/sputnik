import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/nostr.dart';

import 'support/in_memory_relay_client.dart';
import 'support/partly_answering_relay_client.dart';

void main() {
  final me = 'ab' * 32;
  final relays = {for (var i = 0; i < 3; i++) 'wss://r$i.example.com'};

  // Each replaceable event a person edits about themselves has its own
  // repository, and all of them go through the same rule.
  final fetchers = <int, Future<OwnEvent> Function(RelayClient)>{
    0: (client) =>
        RelayProfileRepository(client: client).fetchOwnProfileEvent(me, relays),
    10002: (client) => RelayListRepository(client: client).fetch(me, relays),
    10133: (client) =>
        RelayPaymentTargetsRepository(client: client)
            .fetchOwnPaymentTargetsEvent(me, relays),
  };

  for (final entry in fetchers.entries) {
    final kind = entry.key;
    final fetch = entry.value;

    group('kind $kind', () {
      Future<OwnEvent> fetched({required bool found, required int answered}) {
        return fetch(
          PartlyAnsweringRelayClient([
            if (found) fakeEvent(pubkey: me, kind: kind),
          ], answered: answered),
        );
      }

      test(
        'a copy that was found is built on once most relays answered',
        () async {
          expect((await fetched(found: true, answered: 3)).conclusive, isTrue);
          expect((await fetched(found: true, answered: 2)).conclusive, isTrue);
          expect((await fetched(found: true, answered: 1)).conclusive, isFalse);
          expect((await fetched(found: true, answered: 0)).conclusive, isFalse);
        },
      );

      test('nothing found is trusted only when every relay said so', () async {
        expect((await fetched(found: false, answered: 3)).conclusive, isTrue);
        expect((await fetched(found: false, answered: 2)).conclusive, isFalse);
        expect((await fetched(found: false, answered: 1)).conclusive, isFalse);
        expect((await fetched(found: false, answered: 0)).conclusive, isFalse);
      });

      test(
        'says when absence is confirmed, and how many relays answered',
        () async {
          final all = await fetched(found: false, answered: 3);
          expect(all.confirmedAbsent, isTrue);
          expect((all.answeredRelays, all.queriedRelays), (3, 3));

          final most = await fetched(found: false, answered: 2);
          expect(most.confirmedAbsent, isFalse);
          expect(most.mostRelaysAnswered, isTrue);
          expect((most.answeredRelays, most.queriedRelays), (2, 3));

          final few = await fetched(found: false, answered: 1);
          expect(few.confirmedAbsent, isFalse);
          expect(few.mostRelaysAnswered, isFalse);

          // A copy that was found is not an absence, however many answered.
          expect(
            (await fetched(found: true, answered: 3)).confirmedAbsent,
            isFalse,
          );
        },
      );
    });
  }
}
