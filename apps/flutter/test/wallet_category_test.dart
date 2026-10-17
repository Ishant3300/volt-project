import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/wallet_category.dart';

// Mirrors apps/backend/tests/walletCategory.unit.test.js (INDEX pool, Oct 2026).
void main() {
  test('NIFTY / BANKNIFTY / SENSEX futures -> INDEX', () {
    for (final ref in ['NIFTY', 'BANKNIFTY', 'SENSEX', 'NIFTY26OCTFUT', 'BANKNIFTY26NOVFUT', 'SENSEX26OCTFUT', 'nifty']) {
      expect(categoryForSegment('NFO-FUT', ref), 'INDEX', reason: ref);
    }
  });

  test('stock futures and other index futures stay on NSE', () {
    for (final ref in [null, '', 'RELIANCE', 'TCS26OCTFUT', 'FINNIFTY', 'MIDCPNIFTY', 'NIFTYNXT50', 'BANKEX', 'NIFTYNXT5026OCTFUT', 'FINNIFTY26OCTFUT']) {
      expect(categoryForSegment('NFO-FUT', ref), 'NSE', reason: '$ref');
    }
  });

  test('options and other segments ignore the underlying', () {
    expect(categoryForSegment('NFO-OPT', 'NIFTY'), 'NSEOPT');
    expect(categoryForSegment('MCX-FUT', 'NIFTY'), 'MCX');
    expect(categoryForSegment('COMEX-FUT'), 'COMEX');
    expect(categoryForSegment('GLOBAL', 'SENSEX'), 'GLOBAL');
  });

  test('order and allowed pools', () {
    expect(kWalletCategories, ['NSE', 'INDEX', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL']);
    expect(walletLabel('INDEX'), 'INDEX');
    expect(walletLabel('NSEOPT'), 'NSE OPT');
    expect(allowedCategories(['NFO-FUT']), ['NSE', 'INDEX']);
    expect(allowedCategories(['NFO-OPT']), ['NSEOPT']);
    expect(allowedCategories(['SGX', 'MCX-FUT', 'NFO-OPT', 'nfo-fut']), ['NSE', 'INDEX', 'NSEOPT', 'MCX', 'GLOBAL']);
  });
}
