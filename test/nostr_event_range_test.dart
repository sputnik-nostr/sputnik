import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/nostr/hex.dart';
import 'package:sputnik/nostr/keys.dart';
import 'package:sputnik/nostr/models/nostr_event.dart';
import 'package:sputnik/nostr/relay_message_parser.dart';

const _pubkey =
    '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';

NostrEvent _read(String json) =>
    NostrEvent.fromJson(jsonDecode(json) as Map<String, dynamic>);

/// Whether the ID and signature are those of [json] with its numbers hashed
/// exactly as written, which a client with only floating-point numbers
/// couldn't do for the largest ones.
bool _signedCorrectly(String json) {
  final numbers = RegExp(r'"created_at":([^,]+),"kind":([^,]+),');
  final match = numbers.firstMatch(json)!;
  final event = jsonDecode(json) as Map<String, dynamic>;
  final id = sha256.convert(
    utf8.encode('[0,"$_pubkey",${match[1]},${match[2]},[],"range probe"]'),
  );
  return id.toString() == event['id'] &&
      verifySchnorrSignature(
        msg32: Uint8List.fromList(id.bytes),
        sig64: hexDecode(event['sig'] as String),
        pubkey32: hexDecode(_pubkey),
      );
}

Matcher _malformed(String field) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    'Malformed $field',
  ),
);

void main() {
  test('the events used here are all signed correctly', () {
    // The control for the rejections below: only the created_at or the kind
    // makes these events unusable, not their id or signature.
    final all = [
      for (final e in _valid.entries) ('valid ${e.key}', e.value),
      for (final e in _badCreatedAt.entries) ('created_at ${e.key}', e.value),
      for (final e in _badKind.entries) ('kind ${e.key}', e.value),
    ];
    for (final (name, json) in all) {
      expect(_signedCorrectly(json), isTrue, reason: name);
    }
  });

  group('NostrEvent.fromJson', () {
    test('keeps the created_at and the kind of a valid event', () {
      final event = _read(_valid['created_at 1700000000']!);

      expect(
        event.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(event.toJson()['created_at'], 1700000000);
      expect(event.kind, 1);
    });

    test('accepts a created_at of 0', () {
      final event = _read(_valid['created_at 0']!);

      expect(event.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
      expect(event.toJson()['created_at'], 0);
    });

    test('accepts the latest created_at a DateTime can hold', () {
      final event = _read(_valid['created_at 8640000000000']!);

      expect(event.createdAt.toUtc(), DateTime.utc(275760, 9, 13));
      expect(event.toJson()['created_at'], 8640000000000);
    });

    test('accepts the lowest and the highest kind', () {
      expect(_read(_valid['kind 0']!).kind, 0);
      expect(_read(_valid['kind 65535']!).kind, 65535);
    });

    for (final MapEntry(key: value, value: json) in _badCreatedAt.entries) {
      test('rejects a created_at of $value', () {
        expect(() => _read(json), _malformed('created_at'));
      });
    }

    for (final MapEntry(key: value, value: json) in _badKind.entries) {
      test('rejects a kind of $value', () {
        expect(() => _read(json), _malformed('kind'));
      });
    }
  });

  group('RelayMessageParser', () {
    final parser = RelayMessageParser.instance;

    Future<NostrEvent?> parse(String json) async {
      final parsed = await parser.parse(
        '["EVENT","s",$json]',
        subscriptionIds: {'s'},
      );
      return parsed?.event;
    }

    test('delivers valid events', () async {
      for (final name in [
        'created_at 1700000000',
        'created_at 0',
        'kind 0',
        'kind 65535',
      ]) {
        expect(await parse(_valid[name]!), isNotNull, reason: name);
      }
    });

    test(
      'still drops an event dated past the clock at the latest time',
      () async {
        expect(await parse(_valid['created_at 8640000000000']!), isNull);
      },
    );

    test('drops events with a created_at or a kind out of range', () async {
      for (final MapEntry(key: value, value: json) in _badCreatedAt.entries) {
        expect(await parse(json), isNull, reason: 'created_at $value');
      }
      for (final MapEntry(key: value, value: json) in _badKind.entries) {
        expect(await parse(json), isNull, reason: 'kind $value');
      }
    });

    test('does not show a far-future note as an old one', () async {
      // Its created_at is about 2.3e18 seconds, which used to wrap around to a
      // date in 2001 that no check of the clock would notice.
      expect(await parse(_badCreatedAt['2305843010213693952']!), isNull);
    });

    test('keeps parsing after such events, in every worker', () async {
      final bad = [..._badCreatedAt.values, ..._badKind.values];
      for (var i = 0; i < 12; i++) {
        expect(await parse(bad[i % bad.length]), isNull);

        final event = await parse(_valid['created_at 1700000000']!);

        expect(event, isNotNull, reason: 'round $i');
      }
    });
  });
}

/// Valid events, as the key signed them.
const _valid = <String, String>{
  'created_at 1700000000': r'{"id":"4e18e72e88ee803eccbaab604a9d3871f7eaa2ed0a1eec5829e828262baddc22","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":1,"tags":[],"content":"range probe","sig":"1e96941a5c12a7af028ef72e0160b8c00a8757004cb8ba099713654d963e2605dace741a594e68ad0f687f9c97128895be9c3eac04a831a8d4bbee0e67f8e437"}',
  'created_at 0': r'{"id":"5e4b85e87cf43917e1b59cbcfc936a3ec70d32351159ef5520923fc68f155fda","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":0,"kind":1,"tags":[],"content":"range probe","sig":"c746956ad969454f64cfad93b5e84f820418f3c75cd3ee994c64a3bdf1ca99bab065520f6bfa6ef9c030441b9dd75de3124d8f2a294b57b1a98c2b51a95d3468"}',
  'created_at 8640000000000': r'{"id":"e11154eb506a0b0873ab2683912b09e015324c4690b6d7b381f9c484e4b5b7e4","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":8640000000000,"kind":1,"tags":[],"content":"range probe","sig":"7a41b4667add832352374153a6795eb996db7161a29853969a5171a88c0f0e26bef9592766089a06e1fbd357e4a0629d804ee2e2f56ff67a5816660f3fd0971f"}',
  'kind 0': r'{"id":"68a894b1bf1f9514a65340cc30124602ef4864bcfb9896d6d54ece5694708732","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":0,"tags":[],"content":"range probe","sig":"a3eabb767d76c16deb9b537684c67a0ae9628ee0924e379b7fbe86759f04a93e1301c4ddcbbd5bf1913444db1babeeaf33ec9d07a5ca8100da871f116eb7bfed"}',
  'kind 65535': r'{"id":"ed6de6f79482d70699d99d3944c0ad4d690738597210dd7a34e26bf0a8b95a62","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":65535,"tags":[],"content":"range probe","sig":"0b1211c4adb81b01ccaacd247c0b0b59834fd4aca0ce1b5e3d569732c33156e724d3d999817087611aac72ccff1dbf76c0fe8a049040ee2d24064efc0d3fc8d0"}',
};

/// Events with a `created_at` that no client should send.
const _badCreatedAt = <String, String>{
  '-1': r'{"id":"13dfa76fc6d9099e51f33845d01c613598c1cede010b8d03470724b27c07d7f8","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":-1,"kind":1,"tags":[],"content":"range probe","sig":"2ec0596d34fe0f942311c12d28c2cd5e2fca9b0dc718400780edf7787b1e551287ba8df002b25f4ac4e1cd5251372c0f2132ec1f454755046e89b43d32ebab16"}',
  '-8640000000000': r'{"id":"bda592f6715a45daf8891fba67333e2f7d4209ba6bf6a20aa712df45def5f610","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":-8640000000000,"kind":1,"tags":[],"content":"range probe","sig":"ec5863d88f4b28996b54419282f2bdcd69efac75c935a1f020e6194fb00ed4dd2839cc19b826661fe18d3d3b293bf49de995c8a64fb94097baa3490ea6b04860"}',
  '8640000000001': r'{"id":"52ef3a30da3254cdb7d1b7d1abc711c9dc002b097b0cf455fce969c51c13838e","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":8640000000001,"kind":1,"tags":[],"content":"range probe","sig":"ea689af4f4fdf458121f2bc467d4836d36ba7d501dda01c7ed9e6009a5d11cc5e660e4752575f54108d484ff86d38a2feab6314409201c0d851711d9102da903"}',
  '9223372036854775807': r'{"id":"0960cf4ad770edbf71a2413abbe97eb683ee63e25253c614da7a6970775ed5ab","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":9223372036854775807,"kind":1,"tags":[],"content":"range probe","sig":"d030f697892493b95fd10cc1ffb496de463d7b262e1fb6eb8b107a2865014c4af8557de863ed16f3267d8def6f45ea2c175a1d1b6652b4540e231a5bff6500d1"}',
  '2305843010213693952': r'{"id":"f3d87b24236e1ad2dad76ecf57eab2e1de7e69079dd08f11ef0cb1334465517c","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":2305843010213693952,"kind":1,"tags":[],"content":"range probe","sig":"cdddde7e29e54d77c2a11ec61f1e20792ed2395f41bd7cbe8afda1b7cfb4f1a3877edbdeb8626e27e50c9d1573bddb0611f06907af59cb3357fd6a29e6bf0dc0"}',
  '1700000000.5': r'{"id":"b0b3ad2b6388517a24b39f95be7d37e2c80900c64dabc00aeb506c5ef0c1cb86","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000.5,"kind":1,"tags":[],"content":"range probe","sig":"7d998de1ff7cb21c4c3499d7d85c301100765878f23691d9bb9d3fc78c8b9ffc0a03296e3a98d6192383abb043234175257d4cf499bb931d277f37861bc7b9b5"}',
  '1700000000.0': r'{"id":"e66ada439986c1d671d7920ae3b9e2c28de856e526d008168e94a10de68491ed","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000.0,"kind":1,"tags":[],"content":"range probe","sig":"828f4842ab758f5ba34cc3c5f484dca6d742574acb476cde1ff0f6386624980fbd5324a0ec7f82b3f7faae1bfc6b474e640499f55a1ebf312f5bea7d8fd3e036"}',
  '"1700000000"': r'{"id":"bacd32d8fdc2e986785e895dffb39cef50a73edd1cd50974ee93aa7fa8f538f6","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":"1700000000","kind":1,"tags":[],"content":"range probe","sig":"11bc410ea9acf619955b0b8e57295ff635193726c60e243a0ea43394f80d3161d65cc4bd388cd99cab9c6536aea806b0347c0cd36172e632f9188cce0466b57c"}',
  'null': r'{"id":"badc26ac89789826790a6c90dfee06d407e7dc023193433b359f99f40abfc580","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":null,"kind":1,"tags":[],"content":"range probe","sig":"39da4a4083f74646550aa8a4cdd99d19e586620b3e0bfdc597dabefa1842cb54579ce890007ccfba7f02a628ec7b575d0c24a1caea5a6089403a0e890b03caf5"}',
};

/// Events with a `kind` that no client should send.
const _badKind = <String, String>{
  '-1': r'{"id":"e8901898726dee0cdf9858c39da5af51e9f09103ba961f96633b37fd3ef0f8e3","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":-1,"tags":[],"content":"range probe","sig":"b845795b7724a04c1f9ff61d74c596f86845133e3d9dd37dca185975d52bc65fa5afc793daaed3958a76ccefa3a00ddd78262012f673b88f50d6c0bf0e1159c4"}',
  '65536': r'{"id":"fd558fd5ba3773ff3ecc4e554b5beda40e6c8ffa712b86d0be9be5bc77626eaa","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":65536,"tags":[],"content":"range probe","sig":"e607f51c528921c664348b246ba85c0b001693a07375df46728c73281508034da4cbf8875d71a0f2bf00fdeaa9c0a95df77c92ed0bfe4a450157280bc16672b2"}',
  '9007199254740993': r'{"id":"8975f442d54a2f75f6509ed0670773fc622306fdf0e762cba3fc3ac4f5018e54","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":9007199254740993,"tags":[],"content":"range probe","sig":"8dff278a4a38fc2dbed04477326c58c9e1a9b42880bc0724774c3a29d654404915f08ea3d32af2177a649ce5ab620d54363e6aa913787139434f72351d2b61e9"}',
  '1.0': r'{"id":"30b4736e11c3b258e9e1796cbe8fff296d92104ba57bd9ac0a14bafcab5d6161","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":1.0,"tags":[],"content":"range probe","sig":"eaaf18925c93de17b2bacf3c5515bf605f852f8d31bae83464c9299b8c066c8e958247239c5b4873cab436e067f8e85126af4da0a7e8aebf93364d68f835c765"}',
  '"1"': r'{"id":"c4f8c43da435839525242d0818b95f5363c850238c6fdb09e4d33eed753f34c5","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":"1","tags":[],"content":"range probe","sig":"f11fe7e5021bd46d78c7023c3041f3548eb9a443c1f36a8af85615dd62f1dc4294d1ac9ba64c718f355ab93baeeafb18c24e4cfd70c6fed9a367ac6a30f4e57d"}',
  'null': r'{"id":"46d0925360a215e33643eba6c6d89619d344215645e2da15c5a3978f637458d8","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":null,"tags":[],"content":"range probe","sig":"ee1f53eebc2b13c10ce78f54002ff25d5743173284d4e1a942d23e6ed0bdec504c86e0728b53ad4769fdabc489ef770ab6a77bb5e8d55e6788158f50b2f2b248"}',
  'true': r'{"id":"18f605f4db506dd04beb230dfb58de0bd7ae77c168b3fd436a5029825e3bebcb","pubkey":"7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e","created_at":1700000000,"kind":true,"tags":[],"content":"range probe","sig":"0cc4e1a56d36af2fb6716e60efca6b6421d8c38bbd6d05063d4da8f24d06ee3a58d8fb8520a42119a355b2439cf34c467132c61cf39bc60b6d1a869aadaa7f01"}',
};
