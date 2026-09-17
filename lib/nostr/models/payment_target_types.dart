// Single source of truth for the NIP-A3 payment target types.
class PaymentTargetTypeInfo {
  const PaymentTargetTypeInfo({
    required this.displayName,
    this.ticker,
    this.description,
    this.hasDirectUriScheme = false,
    this.tickerIsAlias = false,
  });

  final String displayName;

  // Shown next to the address (e.g. a chip badge, or a settings subtitle).
  final String? ticker;

  // A short hint for types whose name alone doesn't say what they are.
  final String? description;

  // Whether launchUri should use `<type>:<address>` instead of
  // `payto://<type>/<address>`.
  final bool hasDirectUriScheme;

  // Whether this type's ticker is also accepted, on read, as an alternate
  // spelling of the type itself (e.g. "xmr" for "monero").
  final bool tickerIsAlias;
}

const paymentTargetTypes = <String, PaymentTargetTypeInfo>{
  'bitcoin': PaymentTargetTypeInfo(
    displayName: 'Bitcoin',
    ticker: 'BTC',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'lightning': PaymentTargetTypeInfo(
    displayName: 'Lightning',
    ticker: 'LN',
    hasDirectUriScheme: true,
  ),
  'bip352': PaymentTargetTypeInfo(
    displayName: 'BIP-352',
    ticker: 'BTC',
    description: 'Silent payments',
  ),
  'bip353': PaymentTargetTypeInfo(
    displayName: 'BIP-353',
    ticker: 'BTC',
    description: 'DNS addresses',
  ),
  'bitcoincash': PaymentTargetTypeInfo(
    displayName: 'Bitcoin Cash',
    ticker: 'BCH',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'litecoin': PaymentTargetTypeInfo(
    displayName: 'Litecoin',
    ticker: 'LTC',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'monero': PaymentTargetTypeInfo(
    displayName: 'Monero',
    ticker: 'XMR',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'ethereum': PaymentTargetTypeInfo(
    displayName: 'Ethereum',
    ticker: 'ETH',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'zcash': PaymentTargetTypeInfo(
    displayName: 'Zcash',
    ticker: 'ZEC',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'nano': PaymentTargetTypeInfo(
    displayName: 'Nano',
    ticker: 'NANO',
    hasDirectUriScheme: true,
  ),
  'solana': PaymentTargetTypeInfo(
    displayName: 'Solana',
    ticker: 'SOL',
    hasDirectUriScheme: true,
    tickerIsAlias: true,
  ),
  'tron': PaymentTargetTypeInfo(
    displayName: 'Tron',
    ticker: 'TRX',
    tickerIsAlias: true,
  ),
  'paypal': PaymentTargetTypeInfo(displayName: 'PayPal'),
  'venmo': PaymentTargetTypeInfo(displayName: 'Venmo'),
  'revolut': PaymentTargetTypeInfo(displayName: 'Revolut'),
  'cashme': PaymentTargetTypeInfo(
    displayName: 'CashMe',
    description: 'Cash App cashtag',
  ),
};

final Map<String, String> paymentTargetTypeAliases = {
  for (final entry in paymentTargetTypes.entries)
    if (entry.value.tickerIsAlias) entry.value.ticker!.toLowerCase(): entry.key,
};
