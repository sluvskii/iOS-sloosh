import * as Device from 'expo-device';
import { Platform } from 'react-native';

import { collapsDashContainsAv1, collapsDeviceSupportsAv1, CollapsEpisode, CollapsSeason } from '@/native/collaps-parser';

import { PlayerHeaders } from './types';

export function isKnownAv1BrokenDevice(): boolean {
  if (Platform.OS !== 'android') return false;
  const brand = (Device.brand ?? '').toLowerCase();
  const manufacturer = (Device.manufacturer ?? '').toLowerCase();
  const model = (Device.modelName ?? '').toLowerCase();
  const designName = String((Platform as { constants?: { Model?: string } }).constants?.Model ?? '').toLowerCase();

  const isXiaomiFamily =
    brand.includes('xiaomi') ||
    brand.includes('redmi') ||
    brand.includes('poco') ||
    manufacturer.includes('xiaomi');

  const knownBadModel =
    model.includes('220333qpg') ||
    designName.includes('220333qpg') ||
    designName.includes('frost');

  return isXiaomiFamily && knownBadModel;
}

export function findSeasonByNumber(seasons: CollapsSeason[], season: number) {
  return seasons.find((item) => item.season === season) ?? seasons[0] ?? null;
}

export function findEpisodeByNumber(episodes: CollapsEpisode[], episode: number) {
  return episodes.find((item) => item.episode === episode) ?? episodes[0] ?? null;
}

export function normalizeMediaFileId(value: string | undefined, fallback: string): string {
  const safe = (value ?? fallback).toString().trim();
  return safe.replace(/[^a-zA-Z0-9_-]/g, '_') || fallback;
}

export async function shouldPreferHlsForAndroidExo(
  hlsUrl: string | null,
  dashUrl: string | null,
  headers: PlayerHeaders
): Promise<boolean> {
  if (!hlsUrl) return false;
  if (!dashUrl) return true;
  if (Platform.OS !== 'android') return true;
  try {
    const containsAv1 = await collapsDashContainsAv1(dashUrl, {
      referer: headers.Referer,
      origin: headers.Origin,
    });
    if (!containsAv1) return false;

    const supportsAv1 = collapsDeviceSupportsAv1();
    if (!supportsAv1 || isKnownAv1BrokenDevice()) {
      return true;
    }
    return false;
  } catch (error) {
    console.warn('[CollapsNative] collapsDashContainsAv1 failed, fallback to HLS', {
      dashUrl,
      error: error instanceof Error ? error.message : String(error),
    });
    return true;
  }
}
