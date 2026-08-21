import { describe, expect, test } from 'bun:test';
import { normalizeW4Username } from './w4-username';

describe('normalizeW4Username', () => {
  test('leaves a bare username alone', () => {
    expect(normalizeW4Username('nc26jban')).toBe('nc26jban');
    expect(normalizeW4Username('  nc26jban \n')).toBe('nc26jban');
  });

  test('strips the school email domain', () => {
    expect(normalizeW4Username('nc26jban@uwcrcn.no')).toBe('nc26jban');
    expect(normalizeW4Username('  NC26JBAN@UWCRCN.NO  ')).toBe('NC26JBAN');
    expect(normalizeW4Username('nc26jban@uwcrcn.no ')).toBe('nc26jban');
  });

  test('strips any email domain', () => {
    expect(normalizeW4Username('nc26jban@gmail.com')).toBe('nc26jban');
  });

  test('empty local part is empty', () => {
    expect(normalizeW4Username('@uwcrcn.no')).toBe('');
    expect(normalizeW4Username('   ')).toBe('');
  });
});
