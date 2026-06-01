import { CollapsSubtitle } from '@/native/collaps-parser';
import NeomoviesCore from 'neomovies-core';
import * as ExpoFileSystem from 'expo-file-system';

import { PlayerHeaders } from './types';

type ExpoFsFileCtor = new (...args: unknown[]) => {
  uri: string;
  create: (options?: { overwrite?: boolean; intermediates?: boolean }) => void;
  write: (content: string) => void;
};

export function absolutizeHlsManifestUris(manifest: string, manifestUrl: string): string {
  const lines = manifest.split(/\r?\n/);
  return lines
    .map((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return line;
      try {
        return new URL(trimmed, manifestUrl).toString();
      } catch {
        return line;
      }
    })
    .join('\n');
}

export async function rewriteHlsToLocalOrFallback(
  hlsUrl: string,
  voices: string[],
  subtitles: CollapsSubtitle[],
  mediaFileId: string,
  headers: PlayerHeaders
): Promise<string> {
  try {
    const rewrittenHls = await NeomoviesCore.rewriteCollapsHlsFromUrl(
      hlsUrl,
      voices,
      subtitles,
      mediaFileId,
      headers.Referer,
      headers.Origin
    );
    const finalHls = absolutizeHlsManifestUris(rewrittenHls, hlsUrl);
    const FileCtor = (ExpoFileSystem as unknown as { File: ExpoFsFileCtor }).File;
    const Paths = (ExpoFileSystem as unknown as { Paths: { cache: unknown } }).Paths;
    const file = new FileCtor(Paths.cache, `${mediaFileId}.m3u8`);
    file.create({ overwrite: true, intermediates: true });
    file.write(finalHls);
    return file.uri;
  } catch (error) {
    console.warn('[CollapsNative] rewrite HLS failed, fallback to source URL', {
      hlsUrl,
      mediaFileId,
      error: error instanceof Error ? error.message : String(error),
    });
    return hlsUrl;
  }
}

export async function rewriteDashToLocalOrFallback(
  dashUrl: string,
  voices: string[],
  subtitles: CollapsSubtitle[],
  mediaFileId: string,
  headers: PlayerHeaders
): Promise<string | null> {
  try {
    const rewrittenDash = await NeomoviesCore.rewriteCollapsDashFromUrl(
      dashUrl,
      voices,
      subtitles,
      mediaFileId,
      headers.Referer,
      headers.Origin
    );
    const FileCtor = (ExpoFileSystem as unknown as { File: ExpoFsFileCtor }).File;
    const Paths = (ExpoFileSystem as unknown as { Paths: { cache: unknown } }).Paths;
    const file = new FileCtor(Paths.cache, `${mediaFileId}.mpd`);
    file.create({ overwrite: true, intermediates: true });
    file.write(rewrittenDash);
    return file.uri;
  } catch (error) {
    console.warn('[CollapsNative] rewrite DASH failed, fallback to source URL', {
      dashUrl,
      mediaFileId,
      error: error instanceof Error ? error.message : String(error),
    });
    return null;
  }
}
