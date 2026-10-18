import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sputnik/services/ssrf_guard.dart';

import 'support/guard_seams.dart';

void main() {
  restoreGuardSeams();

  group('isOwnNetworkAddress', () {
    // A host with a public IPv4 address and an IPv6 one from a /64.
    final own = [
      InternetAddress('93.184.216.34'),
      InternetAddress('2606:4700:4700:a1:4278:3bff:1d0f:7b0d'),
    ];
    bool isOwn(String ip, [Iterable<InternetAddress>? addresses]) =>
        isOwnNetworkAddress(InternetAddress(ip), addresses ?? own);

    test('matches the addresses of the interfaces themselves', () {
      expect(isOwn('93.184.216.34'), isTrue);
      expect(isOwn('2606:4700:4700:a1:4278:3bff:1d0f:7b0d'), isTrue);
    });

    test('matches an IPv4 address that arrives mapped into IPv6', () {
      expect(isOwn('::ffff:93.184.216.34'), isTrue);
      expect(isOwn('::ffff:5db8:d822'), isTrue); // the same, in hex
      expect(isOwn('::ffff:93.184.216.35'), isFalse);
    });

    test('leaves the neighbours of an IPv4 address alone', () {
      // Interfaces don't report a prefix length, so only the address counts.
      expect(isOwn('93.184.216.33'), isFalse);
      expect(isOwn('93.184.216.35'), isFalse);
      expect(isOwn('93.184.217.34'), isFalse);
    });

    test('matches every address in the /64 of an IPv6 interface address', () {
      expect(isOwn('2606:4700:4700:a1::1'), isTrue);
      expect(isOwn('2606:4700:4700:a1:9fc9:1568:c28c:d30c'), isTrue);
      expect(isOwn('2606:4700:4700:a1:ffff:ffff:ffff:ffff'), isTrue);
    });

    test('leaves IPv6 addresses outside that /64 alone', () {
      expect(isOwn('2606:4700:4700:a2::1'), isFalse);
      expect(isOwn('2606:4700:4700:a0:ffff:ffff:ffff:ffff'), isFalse);
      expect(isOwn('2606:4700:4701:a1::1'), isFalse);
    });

    test('never matches across address families', () {
      // 93.184.216.34 is 5db8:d822 in hex.
      final oddlyAlike = [InternetAddress('5db8:d822::1')];
      expect(isOwn('93.184.216.34', oddlyAlike), isFalse);
      // 38.6.71.0 is 2606:4700 in hex.
      expect(
        isOwn('2606:4700:4700:a1::1', [InternetAddress('38.6.71.0')]),
        isFalse,
      );
    });

    test('matches nothing without interface addresses', () {
      expect(isOwn('93.184.216.34', const []), isFalse);
      expect(isOwn('2606:4700:4700:a1::1', const []), isFalse);
    });
  });

  group('OwnAddresses', () {
    final own = [InternetAddress('93.184.216.34')];

    test(
      'lists the interfaces once for callers that arrive together',
      () async {
        var listings = 0;
        final addresses = OwnAddresses(
          list: () async {
            listings++;
            return own;
          },
        );

        final results = await Future.wait([
          for (var i = 0; i < 5; i++) addresses.addresses,
        ]);

        expect(listings, 1);
        expect(results, everyElement(own));
      },
    );

    test('reuses a listing that is still fresh', () async {
      var listings = 0;
      final addresses = OwnAddresses(
        list: () async {
          listings++;
          return own;
        },
      );

      await addresses.addresses;
      await addresses.addresses;

      expect(listings, 1);
    });

    test('lists again once the listing is older than maxAge', () async {
      var listings = 0;
      final addresses = OwnAddresses(
        maxAge: Duration.zero,
        list: () async => [InternetAddress('93.184.216.${++listings}')],
      );

      expect(await addresses.addresses, [InternetAddress('93.184.216.1')]);
      expect(await addresses.addresses, [InternetAddress('93.184.216.2')]);
    });

    test(
      'treats interfaces that cannot be listed as having no addresses',
      () async {
        var listings = 0;
        final addresses = OwnAddresses(
          list: () async {
            listings++;
            throw const OSError('not allowed', 13);
          },
        );

        expect(await addresses.addresses, isEmpty);
        expect(await addresses.addresses, isEmpty);
        expect(listings, 1); // a failing call is not repeated for every request
      },
    );

    test('lists the interfaces of this machine by default', () async {
      final expected = [
        for (final interface in await NetworkInterface.list(
          includeLoopback: true,
        ))
          ...interface.addresses,
      ];

      expect(await OwnAddresses().addresses, unorderedEquals(expected));
    });
  });
}
